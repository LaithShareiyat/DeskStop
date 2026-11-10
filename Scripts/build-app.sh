#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/DeskStop.app"
# Xcode's build products, kept under build/ (gitignored) rather than Xcode's
# shared DerivedData, so a clean checkout builds the same everywhere.
DERIVED="build/xcode"
PLIST="Resources/Info.plist"

# One binary for Apple silicon and Intel Macs, built with xcodebuild, because
# only Xcode's build records what the App Intents metadata step below needs;
# `swift build` never does, and without that metadata Shortcuts and Spotlight
# can't see DeskStop's actions.
#
# Set DESKSTOP_QUICK=1 to skip Xcode and use a plain `swift build` instead:
# this Mac's own architecture only, and no Shortcuts or Spotlight actions.
# Fine for trying a change; never for a release.
if [[ "${DESKSTOP_QUICK:-0}" != 1 ]]; then
  if ! xcodebuild -version >/dev/null 2>&1; then
    echo "error: Xcode isn't ready, so the universal build with Shortcuts actions can't run." >&2
    echo "error: Install Xcode, then run: sudo xcode-select -s /Applications/Xcode.app && sudo xcodebuild -license accept" >&2
    echo "error: Or set DESKSTOP_QUICK=1 for a quick build without them." >&2
    exit 1
  fi
  echo "Building universal release binary with xcodebuild..."
  xcodebuild -scheme DeskStop -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED" -quiet build
  BIN_SRC="$DERIVED/Build/Products/Release/DeskStop"
  WITH_INTENTS=1
else
  echo "warning: quick build: runs only on Macs like this one, no Shortcuts or Spotlight actions." >&2
  swift build -c release
  BIN_SRC="$(swift build -c release --show-bin-path)/DeskStop"
  WITH_INTENTS=0
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN_SRC" "$APP/Contents/MacOS/DeskStop"
cp "$PLIST" "$APP/Contents/Info.plist"
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# Onboarding media (GIFs) and setup screenshots (PNGs), if any have been added.
cp Resources/*.gif "$APP/Contents/Resources/" 2>/dev/null || true
cp Resources/*.png "$APP/Contents/Resources/" 2>/dev/null || true

# App Intents metadata: Contents/Resources/Metadata.appintents, which is how
# Shortcuts and Spotlight find "Restore Layout" and "Save Desktop to Layout".
# Xcode runs this step for app targets but not for a package's executable,
# so it runs here on the files Xcode's compile left behind, as Xcode would.
if [[ "$WITH_INTENTS" == 1 ]]; then
  echo "Extracting App Intents metadata..."
  OBJ="$DERIVED/Build/Intermediates.noindex/DeskStop.build/Release/DeskStop.build"
  TOOLCHAIN="$(cd "$(dirname "$(xcrun --find swiftc)")/../.." && pwd)"
  ARGS=()
  for ARCH in arm64 x86_64; do
    CONST_LIST="$DERIVED/DeskStop-$ARCH.SwiftConstValuesFileList"
    for NEEDED in "$OBJ/Objects-normal/$ARCH/DeskStop.SwiftFileList" \
                  "$OBJ/Objects-normal/$ARCH/DeskStop_dependency_info.dat"; do
      if [[ ! -f "$NEEDED" ]]; then
        echo "error: expected Xcode build file not found: $NEEDED" >&2
        echo "error: this Xcode version may lay out its build files differently; update the App Intents step in Scripts/build-app.sh." >&2
        exit 1
      fi
    done
    if ! ls "$OBJ/Objects-normal/$ARCH/"*.swiftconstvalues > "$CONST_LIST" 2>/dev/null; then
      echo "error: Xcode wrote no .swiftconstvalues files for $ARCH in $OBJ/Objects-normal/$ARCH" >&2
      echo "error: this Xcode version may lay out its build files differently; update the App Intents step in Scripts/build-app.sh." >&2
      exit 1
    fi
    ARGS+=(--target-triple "$ARCH-apple-macos$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")"
           --dependency-file "$OBJ/Objects-normal/$ARCH/DeskStop_dependency_info.dat"
           --stringsdata-file "$DERIVED/DeskStop-$ARCH.stringsdata"
           --source-file-list "$OBJ/Objects-normal/$ARCH/DeskStop.SwiftFileList"
           --swift-const-vals-list "$CONST_LIST")
  done
  "$TOOLCHAIN/usr/bin/appintentsmetadataprocessor" \
    --toolchain-dir "$TOOLCHAIN" \
    --module-name DeskStop \
    --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
    --xcode-version "$(xcodebuild -version | awk '/Build version/ { print $3 }')" \
    --platform-family macOS \
    --deployment-target "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")" \
    --bundle-identifier "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")" \
    --output "$APP/Contents/Resources" \
    --binary-file "$APP/Contents/MacOS/DeskStop" \
    --compile-time-extraction \
    "${ARGS[@]}"
  if [[ ! -f "$APP/Contents/Resources/Metadata.appintents/extract.actionsdata" ]]; then
    echo "error: no App Intents metadata was written; Shortcuts wouldn't see DeskStop's actions." >&2
    exit 1
  fi
fi

# Ad-hoc ("-") by default. An ad-hoc signature changes with every build, so
# macOS treats each rebuild as a new app and the Finder permission goes stale.
# Signing with one stable certificate avoids that. A self-signed one is
# enough: Keychain Access > Certificate Assistant > Create a Certificate,
# Certificate Type "Code Signing", then e.g.
#   DESKSTOP_SIGN_IDENTITY="DeskStop Dev" ./Scripts/build-app.sh
IDENTITY="${DESKSTOP_SIGN_IDENTITY:--}"
if [[ "$IDENTITY" == "-" ]]; then
  echo "Ad-hoc signing (hardened runtime)..."
else
  echo "Signing as \"$IDENTITY\" (hardened runtime)..."
fi
# Files the build copied in can carry extended attributes (Finder info,
# provenance), which codesign refuses to sign over.
xattr -cr "$APP"
codesign --force --options runtime \
  --entitlements Resources/DeskStop.entitlements \
  --sign "$IDENTITY" "$APP"

echo "Built: $APP ($(lipo -archs "$APP/Contents/MacOS/DeskStop"))"
echo "Run with: open $APP"
