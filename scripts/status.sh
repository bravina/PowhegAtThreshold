#!/usr/bin/env bash
# Quick progress overview: HTCondor queue state + events landed so far.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/../config.sh"

echo "=== POWHEG run status: $(date) ==="
echo ""

echo "-- HTCondor queue --"
if command -v condor_q &>/dev/null; then
    condor_q -format "%d\n" JobStatus 2>/dev/null \
        | awk 'BEGIN{i=0;r=0;h=0;c=0}
               $1==1{i++} $1==2{r++} $1==5{h++} $1==4{c++}
               END{printf "  Idle: %d  Running: %d  Held: %d  Completed: %d\n",i,r,h,c}'
else
    echo "  (condor_q not available on this machine)"
fi
echo ""

echo "-- Output files in $OUTPUT_DIR --"
shopt -s nullglob
files=("$OUTPUT_DIR"/pwgevents-*.lhe.events.gz)
nfiles=${#files[@]}
echo "  $nfiles / $NJOBS LHE files present"
echo ""


echo "-- Gridpack logs (stage completion) --"
for stage in st1-xg1 st1-xg2 st2 st3; do
    logs=("$REPO_DIR/gridpack"/run-${stage}-*.log)
    if [ -e "${logs[0]:-}" ]; then
        ndone=$(grep -l "Thanks for using LHAPDF" "${logs[@]}" 2>/dev/null | wc -l)
        total=${#logs[@]}
        echo "  $stage: $ndone / $total done"
    fi
done
