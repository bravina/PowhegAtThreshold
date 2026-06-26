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
set +u; source "$LCG_SETUP"; set -u
export LHAPDF_DATA_PATH="${LHAPDF_DATA_PATH}:$(lhapdf-config --datadir)"

# Create isolated working directory
mkdir -p "$JOB_DIR"

# Symlink all gridpack files read-only into the job directory.
# The NRC binary uses many more file types than standard POWHEG-BOX
# (pwggrid-NNNN.dat, pwggridinfo-*, virtequiv-*, bornequiv-*, etc.),
# so we symlink everything except input files, stage logs, and LHE output.
for f in "$GRIDDIR"/*; do
    bn="$(basename "$f")"
    [[ "$bn" == powheg.input* ]]  && continue  # job writes its own
    [[ "$bn" == run-st*.log ]]    && continue  # gridpack stage logs
    [[ "$bn" == *.lhe ]]          && continue  # event output
    [[ "$bn" == *.lhe.gz ]]       && continue
    [ -f "$f" ] && ln -sf "$f" "$JOB_DIR/$bn"
done

# Build per-job input: stage 4, correct numevts.
# use-old-grid 0: suppresses the inherited POWHEG-BOX lookup of pwggrids.dat,
# which NRC never creates. The NRC-specific pwggrid-NNNN.dat / pwggridinfo-*
# files are loaded unconditionally through the NRC code path (not via this flag).
sed "s/parallelstage.*/parallelstage 4/ ; \
     s/numevts.*/numevts $NEVENTS_PER_JOB/ ; \
     s/use-old-grid.*/use-old-grid 0/" \
    "$GRIDDIR/powheg.input-save" > "$JOB_DIR/powheg.input"

# Run POWHEG — seed injected via stdin.
# Capture exit code explicitly; without this, set -e+pipefail would fire
# at the pipe line and the error message below would never print.
cd "$JOB_DIR"
EXIT_CODE=0
echo "$SEED" | "$PROG" > run.log 2>&1 || EXIT_CODE=$?

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
