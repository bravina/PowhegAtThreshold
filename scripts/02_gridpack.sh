#!/usr/bin/env bash
# Run POWHEG stages 1–3 (grid setup) on the build machine using GRIDPACK_NCORES
# parallel processes.  Produces gridpack/pwggrids.dat and gridpack/pwgubound.dat,
# which are then used read-only by every HTCondor job.
# Run once; safe to re-run (use-old-grid / use-old-ubound skip completed stages).
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/../config.sh"
set +u; source "$LCG_SETUP"; set -u

GRIDDIR="$REPO_DIR/gridpack"
PROG="$REPO_DIR/POWHEG-BOX-V2/hvq/NonRelativisticCorrections/pwhg_main-thr2"

[ -x "$PROG" ] || { echo "ERROR: binary not found at $PROG — run 01_build.sh first"; exit 1; }

mkdir -p "$GRIDDIR"

echo "=== Setting up gridpack directory: $GRIDDIR ==="
cp "$REPO_DIR/powheg/powheg.input-save" "$GRIDDIR/"

# Generate pwgseeds.dat with enough entries for both gridpack and all HTCondor jobs
NSEEDS=$(( NJOBS > GRIDPACK_NCORES ? NJOBS : GRIDPACK_NCORES ))
seq 1 "$NSEEDS" > "$GRIDDIR/pwgseeds.dat"
echo "  pwgseeds.dat: $NSEEDS entries"

cd "$GRIDDIR"

# Helper: run N parallel POWHEG processes and wait for all to finish
run_parallel() {
    local n=$1
    local logprefix=$2
    for i in $(seq "$n"); do
        echo "$i" | "$PROG" > "${logprefix}-${i}.log" 2>&1 &
    done
    wait
    echo "  all $n processes finished"
}

echo ""
echo "=== Stage 1a: x-grid iteration 1 ($GRIDPACK_NCORES cores) ==="
sed "s/xgriditeration.*/xgriditeration 1/ ; s/parallelstage.*/parallelstage 1/" \
    powheg.input-save > powheg.input
run_parallel "$GRIDPACK_NCORES" "run-st1-xg1"

echo "=== Stage 1b: x-grid iteration 2 ($GRIDPACK_NCORES cores) ==="
sed "s/xgriditeration.*/xgriditeration 2/ ; s/parallelstage.*/parallelstage 1/" \
    powheg.input-save > powheg.input
run_parallel "$GRIDPACK_NCORES" "run-st1-xg2"

echo "=== Stage 2: NLO + upper bounding ($GRIDPACK_NCORES cores) ==="
sed "s/parallelstage.*/parallelstage 2/" powheg.input-save > powheg.input
run_parallel "$GRIDPACK_NCORES" "run-st2"

echo "=== Stage 3: radiation upper bounds ($GRIDPACK_NCORES cores) ==="
sed "s/parallelstage.*/parallelstage 3/" powheg.input-save > powheg.input
run_parallel "$GRIDPACK_NCORES" "run-st3"

echo ""
echo "=== Gridpack complete ==="
for f in pwggrids.dat pwgubound.dat; do
    [ -f "$GRIDDIR/$f" ] && echo "  $f: $(du -sh "$GRIDDIR/$f" | cut -f1)" \
                         || echo "  WARNING: $f missing — check stage logs"
done
