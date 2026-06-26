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

# Extract gridpack into a local scratch directory.
# Running from real local files avoids NFS symlink issues and is faster than NFS.
# $_CONDOR_SCRATCH_DIR is HTCondor's per-job local scratch (cleaned up automatically).
# Fall back to /tmp when testing on the login node.
SCRATCH="${_CONDOR_SCRATCH_DIR:-/tmp}/powheg_${SEED}"
mkdir -p "$SCRATCH"
tar xzf "$REPO_DIR/gridpack.tar.gz" -C "$SCRATCH"

# Build per-job input: stage 4, correct numevts.
# use-old-grid 0: suppresses the inherited POWHEG-BOX lookup of pwggrids.dat,
# which NRC never creates. The NRC-specific pwggrid-NNNN.dat / pwggridinfo-*
# files are loaded unconditionally through the NRC code path.
sed "s/parallelstage.*/parallelstage 4/ ; \
     s/numevts.*/numevts $NEVENTS_PER_JOB/ ; \
     s/use-old-grid.*/use-old-grid 0/" \
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

# Collect output
LHE=$(ls pwgevents-*.lhe.gz 2>/dev/null | head -1)
if [ -z "$LHE" ]; then
    mkdir -p "$REPO_DIR/logs"
    cp run.log "$REPO_DIR/logs/job_${SEED}.log"
    echo "ERROR: no pwgevents-*.lhe.gz found — log at $REPO_DIR/logs/job_${SEED}.log" >&2
    exit 1
fi

mv "$LHE" "$OUTPUT_DIR/"
echo "Job $SEED done: deposited $LHE to $OUTPUT_DIR at $(date)"

# HTCondor cleans up $_CONDOR_SCRATCH_DIR automatically on job exit.
# For /tmp fallback (login node testing), clean up explicitly.
[ -z "${_CONDOR_SCRATCH_DIR:-}" ] && rm -rf "$SCRATCH"
