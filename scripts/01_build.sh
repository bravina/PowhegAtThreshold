#!/usr/bin/env bash
# Clone POWHEG-BOX-V2 + hvq and compile pwhg_main-thr2 using the LCG environment.
# Run once on the UCAF build/login machine.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/../config.sh"

echo "=== Sourcing LCG environment: $LCG_SETUP ==="
source "$LCG_SETUP"
echo "  gfortran: $(gfortran --version | head -1)"
echo "  lhapdf:   $(lhapdf-config --version)"

# Check that the required PDF set is accessible
PDFDIR=$(lhapdf-config --datadir)
if [ ! -d "$PDFDIR/NNPDF30_nlo_as_0118" ]; then
    echo ""
    echo "ERROR: PDF set NNPDF30_nlo_as_0118 not found under $PDFDIR"
    echo "Either it is not installed on this CVMFS instance, or you need to"
    echo "download it to a local directory and set LHAPDF_DATA_PATH, e.g.:"
    echo "  export LHAPDF_DATA_PATH=/your/writable/path:\$LHAPDF_DATA_PATH"
    echo "  lhapdf install NNPDF30_nlo_as_0118"
    exit 1
fi
echo "  PDF set:  NNPDF30_nlo_as_0118 found at $PDFDIR"

echo ""
echo "=== Cloning POWHEG-BOX-V2 ==="
if [ -d "$REPO_DIR/POWHEG-BOX-V2/.git" ]; then
    echo "  already cloned, skipping"
else
    git clone https://gitlab.com/POWHEG-BOX/V2/POWHEG-BOX-V2.git "$REPO_DIR/POWHEG-BOX-V2"
fi

echo "=== Cloning hvq ==="
if [ -f "$REPO_DIR/POWHEG-BOX-V2/hvq/Makefile" ]; then
    echo "  already cloned, skipping"
else
    git clone https://gitlab.com/POWHEG-BOX/V2/User-Processes/hvq.git /tmp/hvq_tmp
    cp -r /tmp/hvq_tmp/. "$REPO_DIR/POWHEG-BOX-V2/hvq/"
    rm -rf /tmp/hvq_tmp
fi

echo "=== Compiling pwhg_main-thr2 ==="
NRC="$REPO_DIR/POWHEG-BOX-V2/hvq/NonRelativisticCorrections"
cd "$NRC"
make pwhg_main-thr2 ANALYSIS=dummy \
     PWHGANAL="pwhg_analysis-dummy.o pwhg_bookhist.o"

echo "=== Creating binary symlink ==="
ln -sf NonRelativisticCorrections/pwhg_main-thr2 \
       "$REPO_DIR/POWHEG-BOX-V2/hvq/pwhg_main-tdecrevise-thr2"

echo ""
echo "=== Build complete ==="
BINARY="$NRC/pwhg_main-thr2"
echo "Binary : $BINARY"
ldd "$BINARY" | grep -i lhapdf || true
