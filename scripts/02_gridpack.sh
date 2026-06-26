#!/usr/bin/env bash
# Run POWHEG stages 1–3 (grid setup) on the build machine using GRIDPACK_NCORES
# parallel processes.  Produces gridpack/pwggrids.dat and gridpack/pwgubound.dat,
# which are then used read-only by every HTCondor job.
# Safe to re-run: stages are skipped if their output files already exist.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/../config.sh"
set +u; source "$LCG_SETUP"; set -u
export LHAPDF_DATA_PATH="${LHAPDF_DATA_PATH}:$(lhapdf-config --datadir)"

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

# Helper: run N parallel POWHEG processes and wait for all to finish.
# Checks every exit code individually — plain `wait` only returns the
# status of the last process, silently swallowing earlier failures.
run_parallel() {
    local n=$1
    local logprefix=$2
    local pids=()
    for i in $(seq "$n"); do
        echo "$i" | "$PROG" > "${logprefix}-${i}.log" 2>&1 &
        pids+=($!)
    done
    local failed=0
    for i in $(seq "$n"); do
        wait "${pids[$((i-1))]}" || { echo "  ERROR: process $i failed (see ${logprefix}-${i}.log)"; failed=$((failed+1)); }
    done
    [ "$failed" -gt 0 ] && { echo "  $failed process(es) failed — aborting"; exit 1; }
    echo "  all $n processes finished"
}

if ls "$GRIDDIR"/pwg-*-stat.dat &>/dev/null; then
    echo ""
    echo "=== Stages 1a+1b+2: pwg-NNNN-stat.dat files exist — skipping ==="
else
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
fi

if ls "$GRIDDIR"/pwgubound-*.dat &>/dev/null; then
    echo "=== Stage 3: pwgubound-NNNN.dat files exist — skipping ==="
else
    echo "=== Stage 3: radiation upper bounds ($GRIDPACK_NCORES cores) ==="
    sed "s/parallelstage.*/parallelstage 3/" powheg.input-save > powheg.input
    run_parallel "$GRIDPACK_NCORES" "run-st3"
fi

echo ""
echo "=== Gridpack complete ==="
N_STAT=$(ls "$GRIDDIR"/pwg-*-stat.dat 2>/dev/null | wc -l)
N_UBD=$(ls "$GRIDDIR"/pwgubound-*.dat 2>/dev/null | wc -l)
echo "  pwg-NNNN-stat.dat files : $N_STAT"
echo "  pwgubound-NNNN.dat files: $N_UBD"
[ "$N_STAT" -eq 0 ] && echo "  WARNING: no stat files — check stage 2 logs"
[ "$N_UBD" -eq 0 ] && echo "  WARNING: no ubound files — check stage 3 logs"
