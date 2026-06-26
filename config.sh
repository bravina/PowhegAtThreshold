#!/usr/bin/env bash
# =============================================================================
# User configuration — fill in these values before running any script.
# All scripts source this file; nothing else needs to be edited.
# =============================================================================

# Absolute path to the directory where this repo is cloned on UCAF
REPO_DIR=/home/ravinab/PowhegAtThreshold

# Where to write the final LHE files (must have enough space — expect ~50 GB)
OUTPUT_DIR=/work/user/ravinab/PowhegAtThreshold

# LCG environment script from CVMFS.
# Adjust the release and platform tag to match the UCAF OS:
#   x86_64-el9-gcc13-opt     → AlmaLinux/Rocky 9 + gcc 13
#   x86_64-centos7-gcc11-opt → CentOS 7 + gcc 11  (older machines)
LCG_SETUP=/cvmfs/sft.cern.ch/lcg/views/LCG_106/x86_64-el9-gcc13-opt/setup.sh

# Path to LHAPDF PDF sets on CVMFS.
# LHAPDF6 searches all colon-separated directories in this variable.
# The LCG view's own datadir is appended automatically by 01_build.sh.
LHAPDF_DATA_PATH=/cvmfs/sft.cern.ch/lcg/external/lhapdfsets/current

# Cores available on the build/login machine for gridpack generation
GRIDPACK_NCORES=80

# HTCondor job array size and events per job  (NJOBS × NEVENTS_PER_JOB = total)
NJOBS=2000
NEVENTS_PER_JOB=11000
