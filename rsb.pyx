"""
Recursive Sparse Blocks matrix format.
librsb interface for Python.
Proof of concept, very limited interface code, tries to resemble scipy.sparse.
Author: Michele Martone
License: GPLv3+
"""

cimport librsb as lr

import numpy as np
cimport numpy as np

from scipy.sparse import csr_matrix
from scipy.sparse import coo_matrix

import scipy as sp

import cython
cimport cython

verbose=0

cpdef rsb_lib_init():
    """Initializes librsb."""
    if verbose:
        print("Initializing librsb")
    return lr.rsb_lib_init(NULL)

cpdef rsb_lib_exit():
    """Finalizes librsb."""
    if verbose:
        print("Finalizing librsb")
    return lr.rsb_lib_exit(NULL)

cpdef rsb_file_mtx_load(const char * filename):
    """Load an rsb_matrix matrix from a Matrix Market file."""
    rm = rsb_matrix()
    lr.rsb_mtx_free(rm.mtxAp) # workaround: shall maybe pass string to rsb_matrix ?
    rm.mtxAp = lr.rsb_file_mtx_load(filename,rm.flagsA,rm.typecode,&rm.errval)
    rm._err_check()
    rm._refresh()
    return rm

cpdef rsb_time():
    """Returns the current time."""
    cdef lr.rsb_time_t rt
    rt = <lr.rsb_time_t>lr.rsb_time()
    return rt

def _print_vec(np.ndarray[np.float_t, ndim=2] x, mylen=0):
    """Prints a vector, eventually overriding its lenfth (which is DANGEROUS)."""
    cdef lr.rsb_coo_idx_t ylv = 0
    cdef lr.rsb_type_t typecode = lr.RSB_NUMERICAL_TYPE_DOUBLE
    ylv = len(x)
    if mylen is not 0:
        ylv = mylen
    return lr.rsb_file_vec_save("/dev/stdout", typecode, <lr.cvoid_ptr>x.data, ylv)

cdef class rsb_matrix:
    cdef lr.rsb_mtx_ptr mtxAp
    cdef lr.rsb_err_t errval
    cdef lr.rsb_type_t typecode 
    cdef lr.rsb_coo_idx_t ncA
    cdef lr.rsb_coo_idx_t nrA
    cdef lr.rsb_nnz_idx_t nnzA # see http://docs.scipy.org/doc/scipy/reference/generated/scipy.sparse.csr_matrix.nnz.html#scipy.sparse.csr_matrix.nnz
    cdef lr.rsb_blk_idx_t nsubmA
    cdef lr.rsb_flags_t flagsA

    def _psf2lsf(self, sym):
        """
        Python Symmetry Flag to librsb Symmetry Flag.
        """
        if sym == 'U':
                return lr.RSB_FLAG_NOFLAGS 
        if sym == 'S':
                return lr.RSB_FLAG_LOWER_SYMMETRIC
        if sym == 'H':
                return lr.RSB_FLAG_LOWER_HERMITIAN
        return lr.RSB_FLAG_NOFLAGS 

    def _prt2lt(self, transA):
        """
        Python RSB transA to librsb transA.
        """
        if transA == 'N':
                return lr.RSB_TRANSPOSITION_N
        if transA == 'T':
                return lr.RSB_TRANSPOSITION_T
        if transA == 'C':
                return lr.RSB_TRANSPOSITION_C
        return lr.RSB_TRANSPOSITION_N

    def _spmm(self,np.ndarray[np.float_t, ndim=2] x, np.ndarray[np.float_t, ndim=2] y, transA='N', double alpha = 1.0, double beta = 1.0, order='F'):
        """
        Sparse Matrix by matrix product based on rsb_spmm().
        """
        cdef lr.rsb_coo_idx_t nrhs = x.shape[1]
        cdef lr.rsb_nnz_idx_t ldB, ldC
        cdef lr.rsb_trans_t transA_ = self._prt2lt(transA)
        cdef lr.rsb_flags_t lr_order = lr.RSB_FLAG_NOFLAGS
        (lr_order,ldB,ldC)=self._otn2obc(order,transA,nrhs)
        assert lr_order==lr.RSB_FLAG_WANT_COLUMN_MAJOR_ORDER or lr_order==lr.RSB_FLAG_WANT_ROW_MAJOR_ORDER
        if x.shape[1] is not y.shape[1]:
           self.errval = lr.RSB_ERR_BADARGS
        else:
           self.errval = lr.rsb_spmm(transA_, &alpha, self.mtxAp, nrhs, lr_order, <lr.cvoid_ptr>x.data, ldB, &beta, <lr.void_ptr>y.data, ldC);
        self._err_check()
        return self.errval

    def _spmv(self,np.ndarray[np.float_t, ndim=1] x, np.ndarray[np.float_t, ndim=1] y, transA='N', double alpha = 1.0, double beta = 1.0, order='F'):
        """
        Sparse Matrix by vector product based on rsb_spmv().
        """
        cdef lr.rsb_coo_idx_t incX = 1, incY = 1
        cdef lr.rsb_trans_t transA_ = self._prt2lt(transA)
        self.errval = lr.rsb_spmv(transA_, &alpha, self.mtxAp, <lr.cvoid_ptr>x.data, incX, &beta, <lr.void_ptr>y.data, incY)
        self._err_check()
        return self.errval

    def _spmv(self,np.ndarray[np.float_t, ndim=2] x, np.ndarray[np.float_t, ndim=2] y, transA='N', double alpha = 1.0, double beta = 1.0, order='F'):
        """
        Sparse Matrix by vector product based on rsb_spmv().
        """
        cdef lr.rsb_coo_idx_t incX = 1, incY = 1
        cdef lr.rsb_trans_t transA_ = self._prt2lt(transA)
        self.errval = lr.rsb_spmv(transA_, &alpha, self.mtxAp, <lr.cvoid_ptr>x.data, incX, &beta, <lr.void_ptr>y.data, incY)
        self._err_check()
        return self.errval

    def __init__(self,arg1=None,shape=None,sym='U'):
        self.nrA=0
        self.ncA=0
        cdef int brA = 0, bcA = 0
        cdef lr.cvoid_ptr VA = NULL
        cdef lr.rsb_flags_t flagsA = lr.RSB_FLAG_NOFLAGS
        self.flagsA = flagsA
        self.mtxAp = NULL
        self.typecode = lr.RSB_NUMERICAL_TYPE_DOUBLE
        self.nnzA=0
        V = None
        I = None
        J = None
        if arg1 is not None:
            if type(arg1) == type(self):
                self = arg1.copy()
                return
            elif type(arg1) == csr_matrix:
                (I,J,V)=sp.sparse.find(arg1)
            elif isinstance(arg1, tuple):
                if len(arg1) == 2 and not isinstance(arg1[1], tuple):
                    shape=[arg1[0], arg1[1]]
                else:
                    if len(arg1) == 2:
                        # (data, ij) format
                        V = arg1[0]
                        I = arg1[1][0]
                        J = arg1[1][1]
                    elif len(arg1) == 3:
                        # (data, indices, indptr) format
                        # raise ValueError("unrecognized %s_matrix constructor usage"% self.format)
                        # here: (data, i,j) format
                        V = arg1[0]
                        I = arg1[1]
                        J = arg1[2]
                    else:
                        raise ValueError("unrecognized %s_matrix constructor usage"% self.format)
        if V is None:
            V = []
            I = []
            J = []

        if shape is None:
            shape=[0,0]
            if len(I):
                shape=[max(I)+1,max(J)+1]

        self.nrA=shape[0]
        self.ncA=shape[1]
        self.flagsA = self.flagsA + self._psf2lsf(sym)
        cdef lr.rsb_coo_idx_t*IA = NULL, *JA = NULL
        cdef np.ndarray VAa = np.array(V,dtype=np.double)
        cdef np.ndarray IAa = np.array(I,dtype=np.int32)
        cdef np.ndarray JAa = np.array(J,dtype=np.int32)
        self.nnzA=len(VAa)
        VA=<lr.void_ptr> VAa.data
        IA=<lr.rsb_coo_idx_t*>IAa.data
        JA=<lr.rsb_coo_idx_t*>JAa.data
        self.mtxAp = lr.rsb_mtx_alloc_from_coo_const(VA,IA,JA,self.nnzA,self.typecode,self.nrA,self.ncA,brA,bcA,self.flagsA,&self.errval)
        self._refresh()
        return
    
    def __str__(self):
        """Return a brief matrix description string."""
        cdef size_t buflen = 256
        cdef char buf[256]
        cdef bytes info = b"["
        self.errval = lr.rsb_mtx_get_info_str(self.mtxAp, "RSB_MIF_MATRIX_INFO__TO__CHAR_P", buf, buflen)
        self._err_check()
        # self.do_print()
        info += buf
        info += b"]"
        return str(info)

    def do_print(self, brief=False):
        """
        Prints the entire matrix (FIXME: currently, to stdout).
        (specific to rsb).
        """
        cdef char* data = "/dev/stdout"
        if (brief):
            print(self.__str__())
        else:
            return self.save(data)

    def _mtx_free(self):
        """
        Frees the matrix.
        """
        # print("Freeing matrix.")
        lr.rsb_mtx_free(self.mtxAp)
        self.mtxAp = NULL

    def __dealloc__(self):
        """Destructor."""
        self._mtx_free()

    def getshape(self):
        """
        Shape of the matrix.
        """
        return (self.nrA,self.ncA)

    @property
    def shape(self):
        """
        Shape of the matrix.
        """
        return self.getshape()

    def __richcmp__(self,f,b):
        """Unfinished."""
	# 0: <
	# 1: <=
	# 2: ==
	# 3: !=
	# 4: >
	# 5: >=
        return False

    def _spmul(self, rsb_matrix other):
        """
        Multiplies two rsb_matrix objects.
        (specific to rsb).
        """
        cdef double alpha = 1.0, beta = 1.0
        cdef lr.rsb_trans_t transA=lr.RSB_TRANSPOSITION_N
        cdef lr.rsb_trans_t transB=lr.RSB_TRANSPOSITION_N
        cdef lr.rsb_flags_t flagsA = lr.RSB_FLAG_NOFLAGS
        rm = rsb_matrix()
        self._err_check()
        rm.mtxAp = lr.rsb_spmsp(self.typecode,transA,&alpha,self.mtxAp,transB,&beta,other.mtxAp,&self.errval)
        self._err_check()
        rm._refresh()
        return rm

    def rescaled(self, double alpha):
        """
        Returned rescaled copy.
        (specific to rsb).
        """
        rm = self.copy()
        rm.rescale(alpha)
        return rm

    def rescale(self, double alpha):
        """
        Rescale this matrix.
        (specific to rsb).
        """
        self.errval = lr.rsb_mtx_upd_vals(self.mtxAp,lr.RSB_ELOPF_MUL,&alpha)
        self._err_check()
        return True

    def __mul__(self, x):
        """
           Multiply by a scalar, dense vector, dense matrix (multivector) or another sparse matrix.
           In the case of a scalar, will return a scaled copy of this matrix.
           In the case of a vector or multivector, order is taken from the operand array; Fortran (column-first) order is recommended.
           In the case of another sparse matrix, this must be conformant in size.
        """
        cdef np.ndarray y
        if type(x) is type(int(1)):
            return self.__mul__(float(x))
        if type(x) is type(float(1)):
            return self.rescaled(x)
        if type(x) is type(self):
            return self._spmul(x)
        if x.ndim is 1:
            y = np.zeros([self.nr()         ],dtype=np.double)
            self._spmv(x,y)
        if x.ndim is 2:
            nrhs=x.shape[1]
            if x.itemsize == x.strides[0]:
                order='F'
            else:
                order='C'
            y = np.zeros([self.shape[0],nrhs],dtype=np.double,order=order)
            self._spmm(x,y)
        return y

    def dot(self, x):
        """
        A wrapper to __mul__ (the * operator).
        (specific to rsb, unlike scipy.sparse).
        """
        return self.__mul__(x)

    def _spadd(self, rsb_matrix other):
        """
        Adds two rsb_matrix objects.
        """
        cdef double alpha = 1.0, beta = 1.0
        cdef lr.rsb_trans_t transA=lr.RSB_TRANSPOSITION_N
        cdef lr.rsb_trans_t transB=lr.RSB_TRANSPOSITION_N
        cdef lr.rsb_flags_t flagsA = lr.RSB_FLAG_NOFLAGS
        rm = rsb_matrix()
        self._err_check()
        rm.mtxAp = lr.rsb_sppsp(self.typecode,transA,&alpha,self.mtxAp,transB,&beta,other.mtxAp,&self.errval)
        self._err_check()
        rm._refresh()
        return rm

    def __add__(self,other):
        """Adds two rsb_matrix objects."""
        return self._spadd(other)

    def __complex__(self,other):
        """Unsupported: at the moment only double precision reals are supported."""
        return False

    def opt_set(self, char * opnp, char * opvp):
        """
        Specifies individual library options in order to fine-tune the library behaviour.
        (specific to rsb).
        """
        self.errval = lr.rsb_lib_set_opt_str(opnp,opvp)
        self._err_check(want_strict=True)
        return True

    def _otn2obc(self,order,transA,nrhs):
        cdef lr.rsb_flags_t lr_order = lr.RSB_FLAG_NOFLAGS
        if order == b'F':
            lr_order=lr.RSB_FLAG_WANT_COLUMN_MAJOR_ORDER
            if transA == b'N':
                ldB=self.ncA
                ldC=self.nrA
            else:
                ldB=self.nrA
                ldC=self.ncA
        else:
            lr_order=lr.RSB_FLAG_WANT_ROW_MAJOR_ORDER
            ldB=nrhs
            ldC=nrhs
        return (lr_order,ldB,ldC)

    def _o2o(self, lr.rsb_flags_t order):
        cdef lr.rsb_flags_t lr_order = lr.RSB_FLAG_NOFLAGS
        if order == b'F':
            lr_order=lr.RSB_FLAG_WANT_COLUMN_MAJOR_ORDER
        else:
            if order == b'C':
                lr_order=lr.RSB_FLAG_WANT_ROW_MAJOR_ORDER
            else:
                assert False
        return lr_order

    def autotune(self, lr.rsb_real_t sf=1.0, lr.rsb_int_t tn=0, lr.rsb_int_t maxr=1, lr.rsb_time_t tmax=2.0, lr.rsb_trans_t transA=b'N', double alpha=1.0, lr.rsb_coo_idx_t nrhs=1, lr.rsb_flags_t order=b'F', double beta=1.0, verbose = False):
        """
        An auto-tuner based on rsb_tune_spmm(): optimizes either the matrix instance, the thread count or both for rsb_spmm() .
        (specific to rsb).
        """
        cdef lr.rsb_nnz_idx_t ldB=0, ldC=0
        cdef lr.rsb_trans_t transA_ = self._prt2lt(transA)
        cdef lr.rsb_flags_t lr_order = self._o2o(order)
        if (verbose == True):
            self.opt_set(b"RSB_IO_WANT_VERBOSE_TUNING",b"1")
        self.errval = lr.rsb_tune_spmm(&self.mtxAp,&sf,&tn,maxr,tmax,transA_,&alpha,NULL,nrhs,lr_order,NULL,ldB,&beta,NULL,ldC);
        assert lr_order==lr.RSB_FLAG_WANT_COLUMN_MAJOR_ORDER or lr_order==lr.RSB_FLAG_WANT_ROW_MAJOR_ORDER
        self._err_check(want_strict=True)
        if (verbose == True):
            self.opt_set(b"RSB_IO_WANT_VERBOSE_TUNING",b"0")
        return True

    def _err_check(self,want_strict=False):
        """
        Basic error checking.
        (specific to rsb).
        """
        cdef size_t buflen = 256
        cdef char buf[256]
        if ( self.errval ):
            lr.rsb_strerror_r(self.errval,buf,buflen)
            self.errval = lr.RSB_ERR_NO_ERROR
            print "Error reported by librsb: ", str(buf,'ascii')
            if want_strict:
                assert False
            return False
        return True

    def _find_block(self,frA,lrA,fcA,lcA):
        """
        Extract sparse block as COO.
        Unfinished.
        """
        cdef lr.rsb_nnz_idx_t rnz = 0
        cdef lr.rsb_nnz_idx_t*rnzp = &rnz
        self.errval = lr.rsb_mtx_get_coo_block(self.mtxAp,NULL,NULL,NULL,frA,lrA,fcA,lcA,NULL,NULL,rnzp,lr.RSB_FLAG_NOFLAGS)
        self._err_check()
        cdef np.ndarray VAa = np.arange(rnz,dtype=np.double)
        cdef np.ndarray JAa = np.arange(rnz,dtype=np.int32)
        cdef np.ndarray IAa = np.arange(rnz,dtype=np.int32)
        cdef lr.void_ptr VA = NULL
        cdef lr.rsb_coo_idx_t*IA = NULL, *JA = NULL
        VA=<lr.void_ptr> VAa.data
        IA=<lr.rsb_coo_idx_t*> IAa.data
        JA=<lr.rsb_coo_idx_t*> JAa.data
        self.errval = lr.rsb_mtx_get_coo_block(self.mtxAp,VA,IA,JA,frA,lrA,fcA,lcA,NULL,NULL,NULL,lr.RSB_FLAG_NOFLAGS)
        self._err_check()
        return (np.array(IAa),np.array(JAa),np.array(VAa))

    def nnz(self):
        """
        Number of nonzero entries.
        (specific to rsb).
        """
        return self.nnzA

    def nsubm(self):
        """
        Number of sparse blocks.
        (specific to rsb).
        """
        return self.nsubmA

    def nr(self):
        """
        Number of rows.
        (specific to rsb).
        """
        return self.nrA

    def nc(self):
        """
        Number of columns.
        (specific to rsb).
        """
        return self.ncA

    def _is_unsymmetric(self):
        """
        RSB matrix symmetry.
        (specific to rsb).
        """
        cdef lr.rsb_flags_t flagsA = lr.RSB_FLAG_NOFLAGS
        self.errval = lr.rsb_mtx_get_info(self.mtxAp, lr.RSB_MIF_MATRIX_FLAGS__TO__RSB_FLAGS_T,&flagsA)
        if ( ( flagsA & (lr.RSB_FLAG_HERMITIAN | lr.RSB_FLAG_SYMMETRIC ) ) == lr.RSB_FLAG_NOFLAGS ):
            return True
        else:
            return False

    def _refresh(self):
        self.errval = lr.rsb_mtx_get_info(self.mtxAp, lr.RSB_MIF_MATRIX_ROWS__TO__RSB_COO_INDEX_T,&self.nrA)
        self.errval = lr.rsb_mtx_get_info(self.mtxAp, lr.RSB_MIF_MATRIX_COLS__TO__RSB_COO_INDEX_T,&self.ncA)
        self.errval = lr.rsb_mtx_get_info(self.mtxAp, lr.RSB_MIF_MATRIX_NNZ__TO__RSB_NNZ_INDEX_T,&self.nnzA)
        self.errval = lr.rsb_mtx_get_info(self.mtxAp, lr.RSB_MIF_MATRIX_TYPECODE__TO__RSB_TYPE_T,&self.typecode)
        self.errval = lr.rsb_mtx_get_info(self.mtxAp, lr.RSB_MIF_LEAVES_COUNT__TO__RSB_BLK_INDEX_T,&self.nsubmA)

    def find(self):
        """
        More or less as scipy.sparse.find(): returns (ia,ja,va).
        (specific to rsb).
        """
        cdef lr.void_ptr VA = NULL
        cdef lr.rsb_coo_idx_t*IA = NULL, *JA = NULL
        cdef np.ndarray VAa = np.arange(self.nnzA,dtype=np.double)
        cdef np.ndarray IAa = np.arange(self.nnzA,dtype=np.int32)
        cdef np.ndarray JAa = np.arange(self.nnzA,dtype=np.int32)
        VA=<lr.void_ptr> VAa.data
        IA=<lr.rsb_coo_idx_t*> IAa.data
        JA=<lr.rsb_coo_idx_t*> JAa.data
        self.errval = lr.rsb_mtx_get_coo(self.mtxAp,VA,IA,JA,lr.RSB_FLAG_NOFLAGS)
        self._err_check()
        return (np.array(IAa),np.array(JAa),np.array(VAa))

    def nonzero(self):
        """
        More or less as scipy.sparse.nonzero(): returns (ia,ja).
        """
        (IA,JA,VA)=self.find()
        return (IA,JA)

    def tril(self):
        """
        Just as scipy.sparse.tril().
        """
        [I,J,V]=self.find()
        return sp.sparse.find(sp.sparse.tril(csr_matrix((V,(I,J)))))

    def triu(self):
        """
        Just as scipy.sparse.triu().
        """
        (I,J,V)=self.find()
        return sp.sparse.find(sp.sparse.triu(csr_matrix((V,(I,J)))))

    def issparse(self):
        """Returns True."""
        return True
    def isspmatrix(self):
        """Returns True."""
        return True
    def isspmatrix_csc(self):
        """Returns False."""
        return False
    def isspmatrix_csr(self):
        """Returns False."""
        return False
    def isspmatrix_bsr(self):
        """Returns False."""
        return False
    def isspmatrix_lil(self):
        """Returns False."""
        return False
    def isspmatrix_dok(self):
        """Returns False."""
        return False
    def isspmatrix_coo(self):
        """Returns False."""
        return False
    def isspmatrix_dia(self):
        """Returns False."""
        return False
    def isspmatrix_rsb(self):
        """
        Returns True.
        (specific to rsb).
        """
        return True

    def save(self, char * filename):
        """
        Saves to a specified file, in the Matrix Market format.
        (specific to rsb).
        """
        self.errval = lr.rsb_file_mtx_save(self.mtxAp,filename)
        self._err_check()
        return True

    def copy(self):
        """
        Returns a copy (clone) of this matrix.
        (specific to rsb).
        """
        cdef lr.rsb_mtx_ptr mtxBp = NULL
        cdef double alpha = 1.0
        cdef lr.rsb_trans_t transA=lr.RSB_TRANSPOSITION_N
        cdef lr.rsb_flags_t flagsA = lr.RSB_FLAG_NOFLAGS
        self.errval = lr.rsb_mtx_clone(&mtxBp,self.typecode,transA,&alpha,self.mtxAp,flagsA)
        rm = rsb_matrix()
        self._err_check()
        rm.mtxAp = mtxBp
        rm.__refresh()
        return rm

    def todense(self,order=None,out=None):
        """
        Returns a dense copy of this matrix.
        (as in scipy.sparse).
        """
        cdef lr.rsb_mtx_ptr mtxBp = NULL
        cdef double alpha = 1.0
        cdef lr.rsb_trans_t transA=lr.RSB_TRANSPOSITION_N
        cdef lr.rsb_flags_t flagsA = lr.RSB_FLAG_NOFLAGS
        #cdef np.ndarray b = np.zeros([self.nrA,self.ncA],dtype=np.double)
        cdef np.ndarray b = np.ascontiguousarray(np.zeros([self.nrA,self.ncA],dtype=np.double))
        cdef lr.rsb_bool_t rowmajorB
        cdef lr.rsb_nnz_idx_t ldB, nrB, ncB
        if ( order is not 'C' ) and ( order is not 'F' ):
            order='C'
        if order is 'C':
            rowmajorB = lr.RSB_BOOL_TRUE
            ldB=self.ncA; nrB=self.nrA; ncB=self.ncA
        else:
            rowmajorB = lr.RSB_BOOL_FALSE
            ldB=self.nrA; nrB=self.nrA; ncB=self.ncA
        self.errval = lr.rsb_mtx_add_to_dense(&alpha,self.mtxAp,ldB,nrB,ncB,rowmajorB,b.data)
        self._err_check()
        return b

    def mini_self_print_test(self):
        """Unfinished."""
        print("*")
        print(self)
        print("*")
        print("a:")
        print(self.find())
        print("a's (1,1):")
        print(self._find_block(1, 1, 1, 1))
        print("a's tril")
        print(self.tril())
        print("a's triu")
        print(self.triu())
        print(" ")

import rsb
rsb.rsb_lib_init()

# vim:et:shiftwidth=4
