#!/usr/bin/env bash
# Per-job wrapper executed by HTCondor.
# $1 = HTCondor $(Process)  (0-indexed); seed = Process + 1
set -euo pipefail

PROCESS=$1
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/../config.sh"

SEED=$(( PROCESS + 1 ))
PROG="$REPO_DIR/POWHEG-BOX-V2/hvq/NonRelativisticCorrections/pwhg_main-thr2"

echo "Job $SEED starting on $(hostname) at $(date)"

# Source LCG so shared libLHAPDF.so is on LD_LIBRARY_PATH
set +u; source "$LCG_SETUP"; set -u
export LHAPDF_DATA_PATH="${LHAPDF_DATA_PATH}:$(lhapdf-config --datadir)"

# Ensure output directory exists before running (avoids silent failure at mv)
mkdir -p "$OUTPUT_DIR"

# Extract gridpack into a local scratch directory.
# Running from real local files avoids NFS symlink issues and is faster than NFS.
# $_CONDOR_SCRATCH_DIR is HTCondor's per-job local scratch (cleaned up automatically).
# Fall back to /tmp when testing on the login node.
SCRATCH="${_CONDOR_SCRATCH_DIR:-/tmp}/powheg_${SEED}"
mkdir -p "$SCRATCH"
tar xzf "$REPO_DIR/gridpack.tar.gz" -C "$SCRATCH"

# manyseeds 1 rejects seed indices > number of lines in pwgseeds.dat.
# The gridpack's pwgseeds.dat has only GRIDPACK_NCORES entries; expand it to
# NJOBS so any seed 1-NJOBS is accepted. Sequential integers give unique RNG seeds.
seq 1 "$NJOBS" > "$SCRATCH/pwgseeds.dat"

# Build per-job input: stage 4, correct numevts.
# use-old-grid 1: NRC stage 4 uses this code path to load pwggrid-NNNN.dat
# (the NRC-specific Vegas grids built during stage 1).  With use-old-grid 0
# the binary takes a different path that fails; the NRC grid loading is
# governed by the xg2 gridinfo files, not the standard POWHEG pwggrids.dat.
sed "s/parallelstage.*/parallelstage 4/ ; \
     s/numevts.*/numevts $NEVENTS_PER_JOB/ ; \
     s/use-old-grid.*/use-old-grid 1/" \
    "$SCRATCH/powheg.input-save" > "$SCRATCH/powheg.input"

# Run POWHEG — seed injected via stdin.
cd "$SCRATCH"
EXIT_CODE=0
echo "$SEED" | "$PROG" > run.log 2>&1 || EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    mkdir -p "$REPO_DIR/logs"
    cp run.log "$REPO_DIR/logs/job_${SEED}.log"
    echo "ERROR: POWHEG exited with code $EXIT_CODE — log at $REPO_DIR/logs/job_${SEED}.log" >&2
    exit $EXIT_CODE
fi

# Collect output.
# NRC compress_lhe 1 produces gzip-compressed content named pwgevents-NNNN.lhe
# (no .gz suffix). Use find (always exits 0) to avoid set -e / pipefail
# triggering when ls receives an unmatched glob as a literal argument.
LHE=$(find . -maxdepth 1 \( -name 'pwgevents-*.lhe.gz' -o -name 'pwgevents-*.lhe' \) | head -1)
if [ -z "$LHE" ]; then
    mkdir -p "$REPO_DIR/logs"
    cp run.log "$REPO_DIR/logs/job_${SEED}.log"
    echo "ERROR: no pwgevents-*.lhe(.gz) found — log at $REPO_DIR/logs/job_${SEED}.log" >&2
    exit 1
fi

DEST="$(basename "$LHE")"
[[ "$DEST" != *.gz ]] && DEST="${DEST}.gz"
mv "$LHE" "$OUTPUT_DIR/$DEST"
echo "Job $SEED done: deposited $DEST to $OUTPUT_DIR at $(date)"

# HTCondor cleans up $_CONDOR_SCRATCH_DIR automatically on job exit.
# For /tmp fallback (login node testing), clean up explicitly.
[ -z "${_CONDOR_SCRATCH_DIR:-}" ] && rm -rf "$SCRATCH"
