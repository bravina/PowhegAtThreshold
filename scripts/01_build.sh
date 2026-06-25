#!/usr/bin/env bash
# Clone POWHEG-BOX-V2 + hvq and compile pwhg_main-thr2 using the LCG environment.
# Run once on the UCAF build/login machine.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/../config.sh"

echo "=== Sourcing LCG environment: $LCG_SETUP ==="
set +u; source "$LCG_SETUP"; set -u
echo "  gfortran: $(gfortran --version | head -1)"
echo "  lhapdf:   $(lhapdf-config --version)"

# Prepend the CVMFS lhapdfsets path so LHAPDF6 finds PDF sets there.
# The LCG view's own datadir (returned by lhapdf-config --datadir) is
# kept as a fallback by appending it after a colon.
export LHAPDF_DATA_PATH="${LHAPDF_DATA_PATH}:$(lhapdf-config --datadir)"
echo "  LHAPDF_DATA_PATH: $LHAPDF_DATA_PATH"

# Verify the required PDF set is reachable
PDF_FOUND=""
IFS=: read -ra PDFDIRS <<< "$LHAPDF_DATA_PATH"
for dir in "${PDFDIRS[@]}"; do
    [ -d "$dir/NNPDF30_nlo_as_0118" ] && PDF_FOUND="$dir" && break
done
if [ -z "$PDF_FOUND" ]; then
    echo ""
    echo "ERROR: NNPDF30_nlo_as_0118 not found in any directory on LHAPDF_DATA_PATH"
    echo "  $LHAPDF_DATA_PATH"
    exit 1
fi
echo "  PDF set:  NNPDF30_nlo_as_0118 found at $PDF_FOUND"

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
