#!/usr/bin/env bash
# Verify output completeness and count total events.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/../config.sh"

TOTAL_EXPECTED=$(( NJOBS * NEVENTS_PER_JOB ))

echo "=== Checking $OUTPUT_DIR ==="
shopt -s nullglob
files=("$OUTPUT_DIR"/pwgevents-*.lhe.events.gz)
nfiles=${#files[@]}
echo "  LHE files present : $nfiles / $NJOBS"

if (( nfiles == 0 )); then
    echo "  No files found yet."
    exit 0
fi

echo "  Counting events (this may take a minute) ..."
total=$(zcat "${files[@]}" | grep -c "<event>")
echo "  Events counted    : $total / $TOTAL_EXPECTED"

if (( nfiles < NJOBS )); then
    missing=$(( NJOBS - nfiles ))
    echo ""
    echo "  $missing jobs have not yet deposited output."
fi

if (( total == TOTAL_EXPECTED )); then
    echo ""
    echo "  All $TOTAL_EXPECTED events accounted for. Generation complete."
fi
