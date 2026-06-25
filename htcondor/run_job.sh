#!/usr/bin/env bash
# Per-job wrapper executed by HTCondor.
# $1 = HTCondor $(Process)  (0-indexed); seed = Process + 1
set -euo pipefail

PROCESS=$1
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/../config.sh"

SEED=$(( PROCESS + 1 ))
PROG="$REPO_DIR/POWHEG-BOX-V2/hvq/NonRelativisticCorrections/pwhg_main-thr2"
GRIDDIR="$REPO_DIR/gridpack"
JOB_DIR="$REPO_DIR/jobs/job_${SEED}"

echo "Job $SEED starting on $(hostname) at $(date)"

# Source LCG so shared libLHAPDF.so is on LD_LIBRARY_PATH
source "$LCG_SETUP"

# Create isolated working directory
mkdir -p "$JOB_DIR"

# Symlink shared grid files (read-only; no copying)
ln -sf "$GRIDDIR/pwggrids.dat"  "$JOB_DIR/pwggrids.dat"
ln -sf "$GRIDDIR/pwgubound.dat" "$JOB_DIR/pwgubound.dat"
ln -sf "$GRIDDIR/pwgseeds.dat"  "$JOB_DIR/pwgseeds.dat"

# Build per-job input: stage 4, correct numevts, reuse grid
sed "s/parallelstage.*/parallelstage 4/ ; \
     s/numevts.*/numevts $NEVENTS_PER_JOB/" \
    "$GRIDDIR/powheg.input-save" > "$JOB_DIR/powheg.input"

# Run POWHEG — seed injected via stdin
cd "$JOB_DIR"
echo "$SEED" | "$PROG" > run.log 2>&1
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    echo "ERROR: POWHEG exited with code $EXIT_CODE — leaving $JOB_DIR for inspection" >&2
    exit $EXIT_CODE
fi

# Collect output atomically
LHE=$(ls pwgevents-*.lhe.gz 2>/dev/null | head -1)
if [ -z "$LHE" ]; then
    echo "ERROR: no pwgevents-*.lhe.gz found in $JOB_DIR — leaving for inspection" >&2
    exit 1
fi

mv "$LHE" "$OUTPUT_DIR/"
echo "Job $SEED done: deposited $LHE to $OUTPUT_DIR at $(date)"

# Clean up
cd "$REPO_DIR"
rm -rf "$JOB_DIR"
