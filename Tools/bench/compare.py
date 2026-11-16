#!/usr/bin/env python3
"""Prints each measure of the newest benchmark run beside the run before it on the same Mac model,
and warns when one got more than 20% slower (F19). Usage: compare.py Tools/bench/history.csv"""
import csv
import sys

rows = list(csv.DictReader(open(sys.argv[1])))
if not rows:
    sys.exit(0)
machine = rows[-1]["machine"]
# One `make bench` is one run: its rows share the commit and are written within a few minutes.
runs = []  # [(label, {measure: ms})], oldest first
for row in rows:
    if row["machine"] != machine:
        continue
    label = f"{row['commit']} {row['date'][:13]}h"
    if not runs or runs[-1][0] != label or row["measure"] in runs[-1][1]:
        runs.append((label, {}))
    runs[-1][1][row["measure"]] = float(row["milliseconds"])
latest = runs[-1]
previous = runs[-2] if len(runs) > 1 else None
print(f"Benchmarks on {machine}: {latest[0]}" + (f", compared with {previous[0]}" if previous else ""))
slower = False
for measure, ms in sorted(latest[1].items()):
    before = previous[1].get(measure) if previous else None
    if before:
        change = (ms - before) / before * 100
        flag = "  <-- slower" if change > 20 else ""
        slower |= change > 20
        print(f"  {measure:24} {ms:8.2f} ms  (was {before:.2f}, {change:+.0f}%){flag}")
    else:
        print(f"  {measure:24} {ms:8.2f} ms")
if slower:
    print("Some measures are more than 20% slower than last time: look into it before committing.")
