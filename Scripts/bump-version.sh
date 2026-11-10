#!/usr/bin/env bash
# Cut a release: Scripts/bump-version.sh 1.2.0
#
# Sets the version in Resources/Info.plist, bumps the build number, commits,
# and tags.
# Pushing the tag (the script prints the command) makes GitHub Actions build
# and publish the release, which every installed copy is then offered.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
  echo "usage: $0 <version>   e.g. $0 1.2.0" >&2
  exit 1
fi
TAG="v$VERSION"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: commit or stash your changes first." >&2
  exit 1
fi
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "error: tag $TAG already exists." >&2
  exit 1
fi

PLIST="Resources/Info.plist"
BUILD="$(perl -0ne 'print $1 if /<key>CFBundleVersion<\/key>\s*<string>(\d+)<\/string>/' "$PLIST")"
NEXT_BUILD=$(( ${BUILD:-0} + 1 ))

# perl rather than sed -i, whose flags differ between macOS and Linux.
perl -0pi -e "s|(<key>CFBundleShortVersionString</key>\s*<string>)[^<]*(</string>)|\${1}$VERSION\${2}|" "$PLIST"
perl -0pi -e "s|(<key>CFBundleVersion</key>\s*<string>)[^<]*(</string>)|\${1}$NEXT_BUILD\${2}|" "$PLIST"

git add "$PLIST"
git commit -q -m "chore: release $VERSION"
git tag -a "$TAG" -m "DeskStop $VERSION"

echo "Version $VERSION (build $NEXT_BUILD) committed and tagged $TAG."
echo "Publish it with:"
echo "  git push && git push origin $TAG"
