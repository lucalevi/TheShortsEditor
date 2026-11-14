#!/bin/zsh
# Writes Packages/EditorCore/Tests/EditorCoreTests/Golden/v<N>.shortsproject: a project file as
# saved by the last commit of each project-file version, made with Tools/golden/GoldenWriter.swift.
# These files are frozen: run this only to add a file for a NEW version (pass its number and the
# commit), never to remake old ones.
#
#   Tools/golden/make-golden.sh            # every version listed below that has no file yet
#   Tools/golden/make-golden.sh 9 abc1234  # one version from one commit
set -euo pipefail
root=${0:A:h:h:h}
out=$root/Packages/EditorCore/Tests/EditorCoreTests/Golden
work=${TMPDIR:-/tmp}/shorts-golden
mkdir -p $out $work

# The last commit at which each version was current (the one before the next bump; HEAD-era for 8).
typeset -A commits=(
  1 04737ab  2 b764acb  3 703da25  4 a9b98a9  5 4b5f09e  6 68d961b  7 5b8c371  8 8870268
)
[[ $# -eq 2 ]] && commits=($1 $2)

for version in ${(onk)commits}; do
  target=$out/v$version.shortsproject
  [[ -e $target ]] && { echo "v$version exists, kept"; continue; }
  commit=${commits[$version]}
  tree=$work/v$version
  rm -rf $tree
  git -C $root worktree add --detach --force $tree $commit >/dev/null
  cp $root/Tools/golden/GoldenWriter.swift $tree/Packages/EditorCore/Tests/EditorCoreTests/
  flags=()
  for v in {1..$version}; do flags+=(-Xswiftc -DGOLDEN_V$v); done
  grep -q "public var created" $tree/Packages/EditorCore/Sources/EditorCore/ProjectFile.swift && flags+=(-Xswiftc -DGOLDEN_NAMED)
  echo "v$version from $commit…"
  (cd $tree/Packages/EditorCore && GOLDEN_OUT=$target swift test --filter writeGoldenProject $flags >$work/v$version.log 2>&1) \
    || { echo "v$version failed, see $work/v$version.log"; exit 1; }
  git -C $root worktree remove --force $tree
  echo "v$version written"
done
