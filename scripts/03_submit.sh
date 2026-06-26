#!/usr/bin/env bash
# Submit the HTCondor job array.
# Requires gridpack.tar.gz to exist (produced by 02_gridpack.sh).
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/../config.sh"

TARBALL="$REPO_DIR/gridpack.tar.gz"
[ -f "$TARBALL" ] || { echo "ERROR: $TARBALL missing — run 02_gridpack.sh first"; exit 1; }

mkdir -p "$REPO_DIR/logs" "$OUTPUT_DIR"

echo "=== Submitting $NJOBS HTCondor jobs ($NEVENTS_PER_JOB events each) ==="
echo "    Output → $OUTPUT_DIR"

# Substitute config values into the submit file and pipe straight to condor_submit
sed \
    -e "s|REPO_DIR_PLACEHOLDER|$REPO_DIR|g" \
    -e "s|NJOBS_PLACEHOLDER|$NJOBS|g" \
    "$REPO_DIR/htcondor/job.sub" | condor_submit

echo "Monitor with: bash $REPO_DIR/scripts/status.sh"
