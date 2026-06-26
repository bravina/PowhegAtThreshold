# POWHEG hvq NRC — ttbar threshold event generation

Generates ttbar events at NLO QCD with non-relativistic threshold corrections
(`pwhg_main-thr2`) using [POWHEG-BOX-V2](https://gitlab.com/POWHEG-BOX/V2/POWHEG-BOX-V2)
and the [hvq](https://gitlab.com/POWHEG-BOX/V2/User-Processes/hvq) user process.
Output is gzipped LHE files for downstream Pythia showering.

Physics settings: 13 TeV pp, mt = 172.5 GeV, NNPDF3.0 NLO (LHAID 260000),
dileptonic top decays (e+μ), full NRC (`ithreshold 33`) plus 10 reweighting
variations for threshold uncertainty studies.

## Requirements

- CVMFS with an LCG release providing gfortran and LHAPDF6
  (default: `LCG_106/x86_64-el9-gcc13-opt`)
- Shared filesystem visible from all build and worker machines
- HTCondor cluster (or several machines with SSH access — see below)

## Quick start

```
1. Clone this repo onto the UCAF shared filesystem
2. Edit config.sh
3. bash scripts/01_build.sh       # compile once on build machine
4. bash scripts/02_gridpack.sh    # grid setup (~few hours, produces gridpack.tar.gz)
5. bash scripts/03_submit.sh      # submit HTCondor array
6. bash scripts/status.sh         # monitor progress
7. bash scripts/04_collect.sh     # verify event count when done
```

## Repository layout

```
config.sh                  ← fill this in first
powheg/
  powheg.input-save        ← physics input card (NRC settings)
scripts/
  01_build.sh              ← clone POWHEG repos + compile binary
  02_gridpack.sh           ← run stages 1–3, produce gridpack.tar.gz
  03_submit.sh             ← submit HTCondor array
  04_collect.sh            ← verify output completeness
  status.sh                ← live progress monitor
htcondor/
  job.sub                  ← HTCondor submit file template
  run_job.sh               ← per-job wrapper (stage 4 + cleanup)
```

Generated at runtime (gitignored):

```
POWHEG-BOX-V2/             ← cloned by 01_build.sh
gridpack/                  ← grid files from 02_gridpack.sh
gridpack.tar.gz            ← tarball created by 02_gridpack.sh, used by jobs
logs/                      ← HTCondor stdout/stderr and failed-job logs
<OUTPUT_DIR>/              ← final LHE files (set in config.sh)
```

## Step-by-step

### 1 — Edit config.sh

```bash
REPO_DIR=/your/shared/path/PowhegAtThreshold   # where this repo is cloned
OUTPUT_DIR=/your/shared/path/lhe_output        # where LHE files are deposited
LCG_SETUP=/cvmfs/sft.cern.ch/lcg/views/LCG_106/x86_64-el9-gcc13-opt/setup.sh
GRIDPACK_NCORES=80     # cores on the build/login machine
NJOBS=2000             # HTCondor jobs (no gridpack rebuild needed to change this)
NEVENTS_PER_JOB=11000  # events per job (add ~10% buffer over target for Pythia)
```

### 2 — Build (once on login/build machine)

```bash
bash scripts/01_build.sh
```

Sources the LCG environment, clones POWHEG-BOX-V2 and hvq, compiles `pwhg_main-thr2`,
and verifies that `NNPDF30_nlo_as_0118` is accessible on LHAPDF_DATA_PATH.

### 3 — Generate the gridpack (once on build machine)

```bash
bash scripts/02_gridpack.sh
```

Runs POWHEG stages 1–3 in parallel using `GRIDPACK_NCORES` processes, then
packages everything into `gridpack.tar.gz`. With 80 cores and the default
ATLAS integration settings expect 2–3 hours total. Safe to re-run: each stage
is skipped if its output files already exist.

Output: `gridpack/` containing per-seed grid files, and `gridpack.tar.gz`.

### 4 — Submit HTCondor jobs

```bash
bash scripts/03_submit.sh
```

Submits `NJOBS` independent jobs. Each job:
1. Extracts `gridpack.tar.gz` into `$_CONDOR_SCRATCH_DIR` (local worker disk)
2. Runs POWHEG stage 4 with a unique seed
3. Renames the output (`pwgevents-NNNN.lhe` → `pwgevents-NNNN.lhe.gz`) and
   moves it to `OUTPUT_DIR`

Failed jobs save their log to `logs/job_<seed>.log` and exit non-zero for
HTCondor to record.

### 5 — Monitor

```bash
bash scripts/status.sh
watch -n 60 bash scripts/status.sh
```

### 6 — Verify

```bash
bash scripts/04_collect.sh
```

Counts LHE files and total events, lists any missing seeds.

## Running without HTCondor (multi-machine fallback)

If HTCondor is unavailable, use `scripts/run_local.sh` to run jobs directly on
worker machines. It divides `NJOBS` into contiguous partitions and keeps up to
`NCORES` processes running in parallel on the local machine.

SSH to each machine and start it in a `tmux` or `screen` session:

```bash
# machine 0 (processes 0–499, seeds 1–500)
bash scripts/run_local.sh 0

# machine 1 (processes 500–999, seeds 501–1000)
bash scripts/run_local.sh 1

# machine 2 (processes 1000–1499, seeds 1001–1500)
bash scripts/run_local.sh 2

# machine 3 (processes 1500–1999, seeds 1501–2000)
bash scripts/run_local.sh 3
```

Custom number of machines or cores: `bash scripts/run_local.sh <id> <n_machines> <n_cores>`.

Each job extracts `gridpack.tar.gz` to `$_CONDOR_SCRATCH_DIR/powheg_<seed>` (falls
back to `/tmp`). With 50 parallel jobs the extracted gridpack occupies roughly
25 GB of scratch space. If `/tmp` is small, set `_CONDOR_SCRATCH_DIR` first:

```bash
export _CONDOR_SCRATCH_DIR=/scratch/$USER
bash scripts/run_local.sh 0
```

## Resubmitting failed jobs

```bash
source config.sh
for i in $(seq 1 $NJOBS); do
    f=$(printf "pwgevents-%04d.lhe.gz" $i)
    [ -f "$OUTPUT_DIR/$f" ] || echo "missing: seed $i"
done
```

Resubmit missing seeds by adjusting `NJOBS` or submitting a targeted array.

## Scaling up

`NJOBS` can be increased freely without rebuilding the gridpack — each stage 4
job only needs a unique seed (provided via stdin) and reads the shared
`gridpack.tar.gz`. With `NJOBS=2000` and `NEVENTS_PER_JOB=11000` the total
yield is 22M events.

## Output format

Each `pwgevents-NNNN.lhe.gz` is a gzipped Les Houches Event File. Each event
carries 10 extra weights for threshold uncertainty studies:

| Weight ID | Setting | Description |
|-----------|---------|-------------|
| nominal | `ithreshold 33` | Exact Sommerfeld factor + delta term (full NRC) |
| 2  | `ithreshold 0`  | No threshold corrections (pure NLO) |
| 3  | `ithreshold 1`  | + NLO αs/β Coulomb term |
| 4  | `ithreshold 2`  | + NNLO αs²/β² Coulomb term |
| 5  | `ithreshold 3`  | + NNNLO αs³ δ(E) term |
| 6  | `ithreshold 4`  | + NNNNLO αs⁴ term |
| 7  | `ithreshold 6`  | Perturbative Coulomb expansion through 6th order in αs/β |
| 8  | `ithreshold 34` | Delta term only (+ Born) |
| 9  | `ithreshold 35` | Sommerfeld factor only |
| 10 | `ithreshold 33`, `coulombScaleFact 0.5` | Full NRC, Coulomb scale ÷ 2 |
| 11 | `ithreshold 33`, `coulombScaleFact 2`   | Full NRC, Coulomb scale × 2 |

Values 1–6 are cumulative fixed-order terms in the perturbative expansion of the
Coulomb Green's function; together they show convergence toward the exact
Sommerfeld resummation (33). Weights 8 and 9 decompose the full NRC into its
two components (Sommerfeld factor and delta term).
