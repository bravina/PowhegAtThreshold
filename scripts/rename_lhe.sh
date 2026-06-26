#!/usr/bin/env bash
# Rename pwgevents-NNNN.lhe.gz → pwgevents-NNNN.lhe.events.gz in OUTPUT_DIR.
# Decompresses, renames .lhe → .lhe.events, recompresses.
# Already-renamed files (.lhe.events.gz) are skipped.
# Usage: bash scripts/rename_lhe.sh [n_parallel]

set -uo pipefail

NPAR=${1:-50}

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/../config.sh"

shopt -s nullglob
files=("$OUTPUT_DIR"/pwgevents-*.lhe.gz)
n=${#files[@]}

echo "=== rename_lhe: $n files to process in $OUTPUT_DIR ($NPAR parallel) ==="
echo "    Started: $(date)"
[ "$n" -eq 0 ] && { echo "Nothing to do."; exit 0; }

printf '%s\0' "${files[@]}" | \
    xargs -0 -P "$NPAR" -I{} bash -c '
        f="$1"
        stem="${f%.lhe.gz}"
        # Skip if already renamed (e.g. partial re-run)
        [ -f "${stem}.lhe.events.gz" ] && { echo "skip: $(basename "$stem")"; exit 0; }
        gunzip "$f" \
            && mv "${stem}.lhe" "${stem}.lhe.events" \
            && gzip "${stem}.lhe.events" \
            && echo "done: $(basename "${stem}").lhe.events.gz"
    ' _ {}

echo ""
shopt -s nullglob
done_files=("$OUTPUT_DIR"/pwgevents-*.lhe.events.gz)
echo "=== Done: ${#done_files[@]} / $n files renamed — $(date) ==="
