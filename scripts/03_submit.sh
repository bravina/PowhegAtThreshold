#!/usr/bin/env bash
# Submit the HTCondor job array.
# Requires gridpack/pwggrids.dat and gridpack/pwgubound.dat to exist.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/../config.sh"

GRIDDIR="$REPO_DIR/gridpack"

for f in pwggrids.dat pwgubound.dat; do
    [ -f "$GRIDDIR/$f" ] || { echo "ERROR: $GRIDDIR/$f missing — run 02_gridpack.sh first"; exit 1; }
done

mkdir -p "$REPO_DIR/logs" "$OUTPUT_DIR"

echo "=== Submitting $NJOBS HTCondor jobs ($NEVENTS_PER_JOB events each) ==="
echo "    Output → $OUTPUT_DIR"

# Substitute config values into the submit file and pipe straight to condor_submit
sed \
    -e "s|REPO_DIR_PLACEHOLDER|$REPO_DIR|g" \
    -e "s|NJOBS_PLACEHOLDER|$NJOBS|g" \
    "$REPO_DIR/htcondor/job.sub" | condor_submit

echo "Monitor with: bash $REPO_DIR/scripts/status.sh"
