# POWHEG hvq NRC — ttbar threshold event generation

Generates 10M ttbar events at NLO QCD with non-relativistic threshold corrections
(`pwhg_main-thr2`) using [POWHEG-BOX-V2](https://gitlab.com/POWHEG-BOX/V2/POWHEG-BOX-V2)
and the [hvq](https://gitlab.com/POWHEG-BOX/V2/User-Processes/hvq) user process.
Output is gzipped LHE files for downstream Pythia showering.

Physics settings: 13 TeV pp, mt = 172.5 GeV, NNPDF3.0 NLO (LHAID 260000),
dileptonic top decays, full NRC (`ithreshold 33`) plus 10 reweighting variations
for threshold uncertainty studies.

## Requirements

- CVMFS with an LCG release providing gfortran and LHAPDF6
  (default: `LCG_106/x86_64-el9-gcc13-opt`)
- Shared filesystem visible from both the build machine and HTCondor workers
- HTCondor cluster

## Quick start

```
1. Clone this repo onto the UCAF shared filesystem
2. Edit config.sh
3. bash scripts/01_build.sh       # compile once on build machine
4. bash scripts/02_gridpack.sh    # grid setup on 40 cores (~few hours)
5. bash scripts/03_submit.sh      # submit 1000 HTCondor jobs
6. bash scripts/status.sh         # monitor progress
7. bash scripts/04_collect.sh     # verify 10M events when done
```

## Repository layout

```
config.sh                  ← fill this in first
powheg/
  powheg.input-save        ← physics input card (NRC settings)
scripts/
  01_build.sh              ← clone POWHEG repos + compile binary
  02_gridpack.sh           ← run stages 1–3 on the build machine
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
jobs/                      ← per-job scratch dirs (self-cleaning)
logs/                      ← HTCondor stdout/stderr
<OUTPUT_DIR>/              ← final LHE files (set in config.sh)
```

## Step-by-step

### 1 — Edit config.sh

```bash
REPO_DIR=/your/shared/path/PowhegAtThreshold
OUTPUT_DIR=/your/shared/path/lhe_output
LCG_SETUP=/cvmfs/sft.cern.ch/lcg/views/LCG_106/x86_64-el9-gcc13-opt/setup.sh
GRIDPACK_NCORES=40
NJOBS=1000
NEVENTS_PER_JOB=10000
```

The only mandatory edits are `REPO_DIR` and `OUTPUT_DIR`.  
Adjust `LCG_SETUP` if the UCAF runs a different OS or you want a different LCG release.

### 2 — Build (run once on login/build machine)

```bash
bash scripts/01_build.sh
```

Sources the LCG environment, clones POWHEG-BOX-V2 and hvq, and compiles
`pwhg_main-thr2`. Also checks that the PDF set `NNPDF30_nlo_as_0118` is
accessible. If it is missing from CVMFS, the script prints instructions for
downloading it to a local path.

### 3 — Generate the gridpack (run once on build machine)

```bash
bash scripts/02_gridpack.sh
```

Runs POWHEG stages 1–3 in `gridpack/` using `GRIDPACK_NCORES` parallel
processes. This computes the importance-sampling grid and the upper bounding
functions needed by stage 4.

Expected output: `gridpack/pwggrids.dat` and `gridpack/pwgubound.dat`.

With 40 cores and the default integration settings (`ncall2 1000000`,
`itmx2 5`) expect several hours. The script is safe to re-run: the
`use-old-grid 1` / `use-old-ubound 1` flags in the input card cause
completed stages to be skipped automatically.

### 4 — Submit HTCondor jobs

```bash
bash scripts/03_submit.sh
```

Submits 1000 independent jobs (`NJOBS × NEVENTS_PER_JOB = 10 000 000` events).
Each job:
1. Creates `jobs/job_<seed>/` as its working directory
2. Symlinks the shared grid files (no copying)
3. Runs POWHEG stage 4 with a unique seed
4. Moves `pwgevents-<seed>.lhe.gz` to `OUTPUT_DIR`
5. Removes its working directory

Failed jobs exit with a non-zero code and leave their working directory intact
for inspection.

### 5 — Monitor

```bash
bash scripts/status.sh          # queue state + files landed so far
watch -n 60 bash scripts/status.sh
```

### 6 — Verify

```bash
bash scripts/04_collect.sh
```

Counts LHE files and total events. Reports any missing jobs.

## Resubmitting failed jobs

Identify which seeds are missing:

```bash
source config.sh
for i in $(seq 1 $NJOBS); do
    f=$(printf "pwgevents-%04d.lhe.gz" $i)
    [ -f "$OUTPUT_DIR/$f" ] || echo "missing: seed $i"
done
```

Then rerun manually or resubmit a smaller array targeting only those seeds.

## Output format

Each `pwgevents-NNNN.lhe.gz` is a gzipped Les Houches Event File containing
`NEVENTS_PER_JOB` events. Each event carries 11 weights:

| Weight ID | Setting |
|-----------|---------|
| nominal   | `ithreshold 33` (full NRC) |
| 2–8       | `ithreshold` 0, 1, 2, 3, 4, 6, 34, 35 (perturbative truncations) |
| 10–11     | `coulombScaleFact` 0.5 / 2 (Coulomb scale variation) |

Pythia reads these with `Beams:LHEF` or via the LHEF interface; the extra
weights are available for threshold uncertainty studies.
