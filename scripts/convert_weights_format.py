#!/usr/bin/env python3
"""
Convert POWHEG LHE files from legacy positional <weights> blocks to the
LHE v3 <rwgt><wgt id='...'> format required by HepMC3/Pythia8 in the
ATLAS framework.

Weight IDs are read from the <initrwgt> block already present in each file
header (placed there by rwl_write_rwgt_info regardless of rwl_format_rwgt).
The conversion is purely textual; physics content is unchanged.

Usage:
    python convert_weights_format.py /path/to/lhe/dir [--workers N] [--dry-run]
"""

import argparse
import gzip
import multiprocessing
import os
import re
import sys
from pathlib import Path

try:
    from tqdm import tqdm
except ImportError:
    sys.exit("tqdm is required: pip install tqdm  (or source LCG and it is available)")


def parse_weight_ids(initrwgt_body: str) -> list:
    """Return ordered list of weight IDs from the body of an <initrwgt> block."""
    return re.findall(r"<weight\s+id=['\"]([^'\"]+)['\"]", initrwgt_body, re.IGNORECASE)


def build_rwgt_block(values: list, ids: list) -> str:
    """Construct an <rwgt>...</rwgt> block from parallel value / id lists."""
    lines = ["<rwgt>"]
    for wid, val in zip(ids, values):
        lines.append(f"<wgt id='{wid}'> {val.strip()} </wgt>")
    lines.append("</rwgt>")
    return "\n".join(lines)


def convert_file(path: Path) -> tuple:
    """
    Convert one .lhe.events.gz file in-place.

    Returns (path, status_string) where status is one of:
      'converted (N events)' — rewrote successfully
      'skipped: ...'         — no action needed or possible
      'error: ...'           — something went wrong
    """
    tmp_path = path.with_suffix(".converting.gz")
    try:
        with gzip.open(path, "rt", encoding="utf-8", errors="replace") as fh:
            content = fh.read()

        # Guard: already in v3 format?
        if "<rwgt>" in content:
            return path, "skipped: already in <rwgt> format"
        if "<weights>" not in content:
            return path, "skipped: no <weights> block found"

        # Extract ordered weight IDs from the <initrwgt> header block.
        m = re.search(r"<initrwgt>(.*?)</initrwgt>", content, re.DOTALL | re.IGNORECASE)
        if not m:
            return path, "error: <initrwgt> block not found in header"
        weight_ids = parse_weight_ids(m.group(1))
        if not weight_ids:
            return path, "error: no <weight id=...> entries found in <initrwgt>"

        n_replaced = [0]

        def repl(match):
            raw = match.group(1)
            values = raw.split()
            if len(values) != len(weight_ids):
                raise ValueError(
                    f"event {n_replaced[0] + 1}: got {len(values)} weights "
                    f"but <initrwgt> defines {len(weight_ids)}"
                )
            n_replaced[0] += 1
            return build_rwgt_block(values, weight_ids)

        new_content = re.sub(
            r"<weights>(.*?)</weights>",
            repl,
            content,
            flags=re.DOTALL | re.IGNORECASE,
        )

        if n_replaced[0] == 0:
            return path, "skipped: regex matched no <weights> blocks"

        # Write to temp file then atomically replace the original.
        with gzip.open(tmp_path, "wt", encoding="utf-8", compresslevel=6) as fh:
            fh.write(new_content)
        tmp_path.replace(path)

        return path, f"converted ({n_replaced[0]} events)"

    except Exception as exc:
        try:
            tmp_path.unlink()
        except OSError:
            pass
        return path, f"error: {exc}"


def dry_run_check(path: Path) -> None:
    """Print a human-readable format report for a single file."""
    with gzip.open(path, "rt", encoding="utf-8", errors="replace") as fh:
        sample = fh.read(131072)  # 128 KB — enough to cover any header + first event

    if "<rwgt>" in sample:
        print(f"  {path.name}: already in <rwgt> format — would skip")
        return
    if "<weights>" not in sample:
        print(f"  {path.name}: no weight block found in first 128 KB — would skip")
        return

    m = re.search(r"<initrwgt>(.*?)</initrwgt>", sample, re.DOTALL | re.IGNORECASE)
    ids = parse_weight_ids(m.group(1)) if m else []

    # Count how many weight values the first <weights> block contains.
    wm = re.search(r"<weights>(.*?)</weights>", sample, re.DOTALL | re.IGNORECASE)
    nval = len(wm.group(1).split()) if wm else 0

    status = "OK" if ids and nval == len(ids) else f"MISMATCH (ids={len(ids)}, vals={nval})"
    print(
        f"  {path.name}: would convert — "
        f"{len(ids)} weight IDs {ids}, {nval} values/event [{status}]"
    )


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("directory", help="Directory containing *.lhe.events.gz files")
    ap.add_argument(
        "--workers",
        type=int,
        default=50,
        metavar="N",
        help="Parallel worker processes (default: 50, capped at CPU count and file count)",
    )
    ap.add_argument(
        "--dry-run",
        action="store_true",
        help="Inspect files and report what would be done; make no changes",
    )
    args = ap.parse_args()

    directory = Path(args.directory)
    if not directory.is_dir():
        sys.exit(f"Error: '{directory}' is not a directory")

    files = sorted(directory.glob("*.lhe.events.gz"))
    if not files:
        sys.exit(f"No *.lhe.events.gz files found in {directory}")

    nworkers = min(args.workers, len(files), os.cpu_count() or 1)
    print(f"Found {len(files)} file(s)  |  workers: {nworkers}")

    if args.dry_run:
        print("Dry run — inspecting up to 3 files:")
        for f in files[:3]:
            dry_run_check(f)
        if len(files) > 3:
            print(f"  ... and {len(files) - 3} more")
        print("\nRe-run without --dry-run to convert all files.")
        return

    counts = {"converted": 0, "skipped": 0, "error": 0}
    errors = []

    with multiprocessing.Pool(processes=nworkers) as pool:
        with tqdm(
            total=len(files),
            unit="file",
            desc="Converting",
            dynamic_ncols=True,
        ) as bar:
            for path, status in pool.imap_unordered(convert_file, files):
                if status.startswith("converted"):
                    counts["converted"] += 1
                elif status.startswith("skipped"):
                    counts["skipped"] += 1
                else:
                    counts["error"] += 1
                    errors.append((path.name, status))
                bar.set_postfix(
                    ok=counts["converted"],
                    skip=counts["skipped"],
                    err=counts["error"],
                    refresh=False,
                )
                bar.update(1)

    print(
        f"\nSummary:  converted={counts['converted']}  "
        f"skipped={counts['skipped']}  errors={counts['error']}"
    )

    if errors:
        print("\nFailed files:")
        for name, msg in errors:
            print(f"  {name}: {msg}")
        sys.exit(1)


if __name__ == "__main__":
    main()
