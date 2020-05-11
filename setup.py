import setuptools
from setuptools import setup, Extension
from setuptools.command.build_ext import build_ext
from Cython.Build import cythonize

with open("README.md", "r") as fh:
    long_description = fh.read()

from numpy import get_include
include_dirs = [get_include()]

setup(
    #name="rsb-michele.martone", version = '0.2.202005072047',
    name="rsb", version = '0.2.202005072047',
    #name="rsb", version = '0.2',
    author="Michele Martone",
    author_email="michelemartone@users.sourceforge.net",
    description="PyRSB: a Cython-based Python interface to librsb",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/michelemartone/pyrsb",
    packages=setuptools.find_packages(), # rsb
    classifiers=[
        "Programming Language :: Python :: 3",
        "License :: OSI Approved :: GNU General Public License v3 or later (GPLv3+)",
        "Operating System :: OS Independent",
    ],
    ext_modules = [ Extension("rsb", ["rsb.pyx","librsb.pxd"], libraries=["rsb","z","hwloc","gfortran"], include_dirs = include_dirs ) ],
    setup_requires = ['numpy', 'scipy'],
    install_requires = ['numpy', 'scipy'],
    cmdclass = {'build_ext': build_ext},
    #package_data = { '': ['rsb.pyx','*.py'] },
    include_package_data = True,
    python_requires='>=3.7',
)
