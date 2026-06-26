#!/usr/bin/env bash
# Run stage 4 event generation directly on this machine without HTCondor.
# Divides NJOBS into N_MACHINES contiguous partitions and runs this machine's
# share with up to N_CORES parallel workers.
#
# Usage: bash scripts/run_local.sh <machine_id> [n_machines] [n_cores]
#
# Run once per machine (machine_id is 0-based):
#   machine 0: bash scripts/run_local.sh 0
#   machine 1: bash scripts/run_local.sh 1
#   machine 2: bash scripts/run_local.sh 2
#   machine 3: bash scripts/run_local.sh 3
#
# Each job extracts gridpack.tar.gz to ${_CONDOR_SCRATCH_DIR:-/tmp}/powheg_<seed>.
# With 50 parallel jobs the extracted gridpack occupies significant /tmp space.
# If /tmp is small, export _CONDOR_SCRATCH_DIR to a larger local path first.

set -uo pipefail

MACHINE_ID=${1:?Usage: $0 <machine_id (0-based)> [n_machines] [n_cores]}
NMACHINES=${2:-4}
NCORES=${3:-50}

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/../config.sh"

RUN_JOB="$SCRIPT_DIR/../htcondor/run_job.sh"
[ -f "$REPO_DIR/gridpack.tar.gz" ] || \
    { echo "ERROR: gridpack.tar.gz missing — run 02_gridpack.sh first"; exit 1; }

# Contiguous partition of process indices (0-based, same convention as HTCondor $(Process))
JOBS_PER_MACHINE=$(( (NJOBS + NMACHINES - 1) / NMACHINES ))
FIRST=$(( MACHINE_ID * JOBS_PER_MACHINE ))
LAST=$(( FIRST + JOBS_PER_MACHINE - 1 ))
(( LAST >= NJOBS )) && LAST=$(( NJOBS - 1 ))
NJOBS_HERE=$(( LAST - FIRST + 1 ))

echo "=== run_local: machine $MACHINE_ID/$NMACHINES ==="
echo "    Processes : $FIRST–$LAST  ($NJOBS_HERE jobs, seeds $((FIRST+1))–$((LAST+1)))"
echo "    Parallel  : $NCORES"
echo "    Scratch   : ${_CONDOR_SCRATCH_DIR:-/tmp}"
echo "    Started   : $(date)"
echo ""

running=0
completed=0
failed=0

reap_one() {
    wait -n
    local rc=$?
    running=$(( running - 1 ))
    completed=$(( completed + 1 ))
    if (( rc != 0 )); then failed=$(( failed + 1 )); fi
    printf "  [%d/%d done, %d running, %d failed]\n" \
        "$completed" "$NJOBS_HERE" "$running" "$failed"
}

for process in $(seq "$FIRST" "$LAST"); do
    while (( running >= NCORES )); do
        reap_one
    done
    bash "$RUN_JOB" "$process" &
    running=$(( running + 1 ))
done

while (( running > 0 )); do
    reap_one
done

echo ""
echo "=== Machine $MACHINE_ID done: $NJOBS_HERE jobs, $failed failed — $(date) ==="
(( failed == 0 )) || exit 1
