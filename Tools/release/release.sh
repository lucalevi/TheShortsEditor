#!/bin/zsh
# Builds a shareable Shorts Editor: the Release app, signed ad hoc (no Developer ID, ADR 0011),
# in a .dmg with a link to Applications and "How to open.txt", plus its SHA-256.
#
#   Tools/release/release.sh            # build build/dist/Shorts-Editor-<version>.dmg
#   Tools/release/release.sh --publish  # then tag v<version>, push the tag and make the GitHub Release
#
# The version is MARKETING_VERSION in project.yml (semantic: major.minor.patch); the build number is
# the number of commits, so every release's is higher than the last. The release notes are
# docs/releases/<version>.md, written by hand for people using the app.
set -euo pipefail
cd "${0:A:h}/../.."

publish=0
[[ "${1:-}" == "--publish" ]] && publish=1

version=$(sed -nE 's/^ *MARKETING_VERSION: "([0-9]+\.[0-9]+\.[0-9]+)"$/\1/p' project.yml)
[[ -n "$version" ]] || { echo "MARKETING_VERSION in project.yml isn't major.minor.patch" >&2; exit 1; }
build_number=$(git rev-list --count HEAD)
notes="docs/releases/$version.md"
tag="v$version"
name="Shorts-Editor-$version"
dist="build/dist"
app_dir="build/release-dist"
app="$app_dir/Build/Products/Release/Shorts Editor.app"

[[ -f "$notes" ]] || { echo "Write the release notes first: $notes" >&2; exit 1; }
if (( publish )); then
    [[ -z "$(git status --porcelain)" ]] || { echo "Commit everything before publishing (git status isn't clean)" >&2; exit 1; }
    [[ "$(git branch --show-current)" == "main" ]] || { echo "Publish from main" >&2; exit 1; }
    git fetch --quiet --tags origin
    [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || { echo "Push main first (HEAD isn't origin/main)" >&2; exit 1; }
    ! git rev-parse -q --verify "refs/tags/$tag" >/dev/null || { echo "$tag already exists: raise MARKETING_VERSION" >&2; exit 1; }
fi

echo "▸ Building Shorts Editor $version ($build_number), Release"
xcodegen generate --quiet
rm -rf "$app_dir"
xcodebuild -project TheShortsEditor.xcodeproj -scheme TheShortsEditor -quiet \
    -configuration Release -derivedDataPath "$app_dir" -destination 'generic/platform=macOS' ARCHS=arm64 \
    CURRENT_PROJECT_VERSION="$build_number" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES build

echo "▸ Checking the app"
plist="$app/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$plist")" == "$version" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$plist")" == "$build_number" ]]
codesign --verify --deep --strict "$app"
entitlements=$(codesign -d --entitlements - "$app" 2>/dev/null)
grep -q com.apple.security.app-sandbox <<<"$entitlements"
# Xcode adds get-task-allow (debuggers may attach) to ordinary builds; never to a shared app.
! grep -q get-task-allow <<<"$entitlements" || { echo "The app still allows debugging (get-task-allow)" >&2; exit 1; }
lipo -archs "$app/Contents/MacOS/Shorts Editor" | grep -q arm64

echo "▸ Making the disk image"
mkdir -p "$dist"
stage=$(mktemp -d)
chmod 755 "$stage"
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Shorts Editor.app"
ln -s /Applications "$stage/Applications"
sed "s/{{VERSION}}/$version/g" Tools/release/how-to-open.txt > "$stage/How to open.txt"
dmg="$dist/$name.dmg"
rm -f "$dmg"
hdiutil create -quiet -volname "Shorts Editor $version" -srcfolder "$stage" -fs APFS -format ULFO "$dmg"
hdiutil verify -quiet "$dmg"
(cd "$dist" && shasum -a 256 "$name.dmg" > "$name.dmg.sha256")
echo "  $dmg ($(du -h "$dmg" | cut -f1 | tr -d ' '))"
cat "$dist/$name.dmg.sha256"

if (( publish )); then
    echo "▸ Publishing $tag on GitHub"
    git tag -a "$tag" -m "Shorts Editor $version"
    git push --quiet origin "$tag"
    gh release create "$tag" "$dmg" "$dist/$name.dmg.sha256" --title "Shorts Editor $version" --notes-file "$notes" --verify-tag
fi
