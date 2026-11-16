#!/usr/bin/env python3
"""Coverage floor (F18): fails when line coverage drops below the floor saved in this folder.

    check.py package                 # after `swift test --enable-code-coverage` in Packages/EditorCore
    check.py app <result bundle>     # after `xcodebuild test -resultBundlePath …` (scheme TheShortsEditor)
    check.py <kind> … --raise        # write today's coverage as the new floor (only ever up)

The floor only goes up: when coverage is clearly above it, the check says so, and `make coverage-raise`
writes the new value. Never lower a floor to make a change pass; add tests instead.
"""
import glob
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
# Small differences between runs (timing-dependent paths) shouldn't fail a check.
SLACK = 0.002


def package_coverage():
    package = os.path.join(ROOT, "Packages", "EditorCore")
    # SwiftPM's own JSON covers only the first test binary: export all three together instead.
    path = subprocess.run(["swift", "test", "--show-codecov-path"], cwd=package, capture_output=True, text=True, check=True).stdout.strip()
    codecov = os.path.dirname(path)
    products = os.path.dirname(codecov)
    binaries = sorted(glob.glob(os.path.join(products, "*.xctest", "Contents", "MacOS", "*")))
    command = ["xcrun", "llvm-cov", "export", "-summary-only", "-instr-profile", os.path.join(codecov, "default.profdata"), binaries[0]]
    for binary in binaries[1:]:
        command += ["-object", binary]
    data = json.loads(subprocess.run(command, capture_output=True, text=True, check=True).stdout)["data"][0]["files"]
    covered = total = 0
    per_library = {}
    for item in data:
        name = item["filename"]
        if "/Sources/" not in name:
            continue
        lines = item["summary"]["lines"]
        covered += lines["covered"]
        total += lines["count"]
        library = name.split("/Sources/")[1].split("/")[0]
        c, t = per_library.get(library, (0, 0))
        per_library[library] = (c + lines["covered"], t + lines["count"])
    for library, (c, t) in sorted(per_library.items()):
        print(f"  {library}: {100 * c / t:.1f}% of {t} lines")
    return covered / total


def app_coverage(bundle):
    report = json.loads(subprocess.run(["xcrun", "xccov", "view", "--report", "--json", bundle], capture_output=True, text=True, check=True).stdout)
    for target in report["targets"]:
        if target["name"].endswith(".app"):
            print(f"  {target['name']}: {100 * target['lineCoverage']:.1f}% of {target['executableLines']} lines")
            return target["lineCoverage"]
    sys.exit("No app target in the coverage report: was the scheme run with coverage on?")


def main():
    args = [a for a in sys.argv[1:] if a != "--raise"]
    raising = "--raise" in sys.argv
    if not args or args[0] not in ("package", "app") or (args[0] == "app" and len(args) < 2):
        sys.exit(__doc__)
    kind = args[0]
    coverage = package_coverage() if kind == "package" else app_coverage(args[1])
    floor_file = os.path.join(HERE, f"floor-{kind}.txt")
    floor = float(open(floor_file).read().strip()) if os.path.exists(floor_file) else 0.0
    print(f"Coverage ({kind}): {100 * coverage:.2f}% (floor {100 * floor:.2f}%)")
    if raising:
        if coverage > floor:
            open(floor_file, "w").write(f"{coverage:.4f}\n")
            print(f"Floor raised to {100 * coverage:.2f}%")
        return
    if coverage + SLACK < floor:
        sys.exit(f"Coverage of the {kind} fell below its floor. Add tests for the new code (see research/engineering-excellence.md, F18).")
    if coverage > floor + 0.005:
        print("Coverage is above the floor: run `make coverage-raise` and commit the new floor.")


if __name__ == "__main__":
    main()
