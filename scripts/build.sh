#!/bin/bash
# Builds Oreja de Van Gogh without Xcode.
#
# This machine has Command Line Tools only, and its SwiftPM manifest library is broken, so the
# build calls swiftc directly. The same sources build with `swift build` on a full Xcode install.
#
#   ./scripts/build.sh              # app bundle in build/Oreja.app
#   ./scripts/build.sh --no-sign    # skip ad-hoc signing
#   ./scripts/build.sh --probe      # also build the audio probe used for real capture tests
#   ./scripts/build.sh --harness    # also build the real capture → Music integration harness
#
# Everything is written under build/ (gitignored).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUILD="$ROOT/build"
MODULES="$BUILD/modules"
LIB="$BUILD/lib"
SDK="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"
TARGET="$ARCH-apple-macosx14.2"
SWIFT_FLAGS=(-swift-version 6 -target "$TARGET" -sdk "$SDK" -O -g)
LINK_FLAGS=(-I "$MODULES" -L "$LIB")
SIGN=1
PROBE=0
HARNESS=0

for argument in "$@"; do
    case "$argument" in
        --no-sign) SIGN=0 ;;
        --probe) PROBE=1 ;;
        --harness) HARNESS=1 ;;
        *) echo "usage: $0 [--no-sign] [--probe] [--harness]" >&2; exit 2 ;;
    esac
done

mkdir -p "$MODULES" "$LIB" "$BUILD/bin"

echo "==> OrejaCore"
CORE_SOURCES=()
while IFS= read -r file; do CORE_SOURCES+=("$file"); done < <(find packages/OrejaCore/Sources -name '*.swift' | sort)
swiftc "${SWIFT_FLAGS[@]}" -parse-as-library \
    -module-name OrejaCore \
    -emit-module -emit-library \
    -emit-module-path "$MODULES/OrejaCore.swiftmodule" \
    -o "$LIB/libOrejaCore.dylib" \
    -Xlinker -install_name -Xlinker "@rpath/libOrejaCore.dylib" \
    "${CORE_SOURCES[@]}"

echo "==> OrejaAudio"
AUDIO_SOURCES=()
while IFS= read -r file; do AUDIO_SOURCES+=("$file"); done < <(find packages/OrejaAudio/Sources -name '*.swift' | sort)
swiftc "${SWIFT_FLAGS[@]}" -parse-as-library \
    -module-name OrejaAudio \
    -emit-module -emit-library \
    -emit-module-path "$MODULES/OrejaAudio.swiftmodule" \
    -o "$LIB/libOrejaAudio.dylib" \
    -Xlinker -install_name -Xlinker "@rpath/libOrejaAudio.dylib" \
    "${LINK_FLAGS[@]}" -lOrejaCore -Xlinker -rpath -Xlinker "@loader_path" \
    "${AUDIO_SOURCES[@]}"

echo "==> OrejaMedia"
MEDIA_SOURCES=()
while IFS= read -r file; do MEDIA_SOURCES+=("$file"); done < <(find packages/OrejaMedia/Sources -name '*.swift' | sort)
swiftc "${SWIFT_FLAGS[@]}" -parse-as-library \
    -module-name OrejaMedia \
    -emit-module -emit-library \
    -emit-module-path "$MODULES/OrejaMedia.swiftmodule" \
    -o "$LIB/libOrejaMedia.dylib" \
    -Xlinker -install_name -Xlinker "@rpath/libOrejaMedia.dylib" \
    "${LINK_FLAGS[@]}" -lOrejaCore -Xlinker -rpath -Xlinker "@loader_path" \
    "${MEDIA_SOURCES[@]}"

echo "==> Oreja (menu bar app)"
APP_SOURCES=()
while IFS= read -r file; do APP_SOURCES+=("$file"); done < <(find apps/macos -name '*.swift' | sort)
swiftc "${SWIFT_FLAGS[@]}" -parse-as-library \
    -module-name Oreja \
    "${LINK_FLAGS[@]}" -lOrejaCore -lOrejaAudio -lOrejaMedia \
    -Xlinker -rpath -Xlinker "@executable_path/../Frameworks" \
    -o "$BUILD/bin/Oreja" \
    "${APP_SOURCES[@]}"

if [ "$PROBE" = "1" ]; then
    echo "==> oreja-probe"
    swiftc "${SWIFT_FLAGS[@]}" -parse-as-library \
        "${LINK_FLAGS[@]}" -lOrejaCore -lOrejaAudio \
        -Xlinker -rpath -Xlinker "@loader_path/../lib" \
        -o "$BUILD/bin/oreja-probe" \
        tools/AudioProbe/main.swift
fi

if [ "$HARNESS" = "1" ]; then
    echo "==> oreja-integration"
    swiftc "${SWIFT_FLAGS[@]}" -parse-as-library \
        "${LINK_FLAGS[@]}" -lOrejaCore -lOrejaAudio -lOrejaMedia \
        -Xlinker -rpath -Xlinker "@loader_path/../lib" \
        -o "$BUILD/bin/oreja-integration" \
        tools/IntegrationHarness/main.swift
fi

echo "==> Icon"
swiftc -swift-version 6 -target "$TARGET" -sdk "$SDK" -O -parse-as-library \
    -o "$BUILD/bin/make-icon" tools/IconBuilder/main.swift
"$BUILD/bin/make-icon" "$BUILD" >/dev/null

echo "==> Bundle"
APP="$BUILD/Oreja.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BUILD/bin/Oreja" "$APP/Contents/MacOS/Oreja"
cp packaging/Info.plist "$APP/Contents/Info.plist"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$LIB/libOrejaCore.dylib" "$LIB/libOrejaAudio.dylib" "$LIB/libOrejaMedia.dylib" "$APP/Contents/Frameworks/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ "$SIGN" = "1" ]; then
    # Ad-hoc signatures carry no team identity, so hardened runtime library validation can never
    # accept our own nested dylibs ("different Team IDs"), and the app aborts at launch. Hardened
    # runtime is only meaningful for Developer ID/notarized builds, so it is enabled only when a
    # real signing identity is supplied: OREJA_SIGN_IDENTITY="Developer ID Application: ...".
    IDENTITY="${OREJA_SIGN_IDENTITY:--}"
    if [ "$IDENTITY" = "-" ]; then
        echo "==> Ad-hoc signing (no hardened runtime: ad-hoc has no team identity)"
        SIGN_OPTIONS=()
    else
        echo "==> Signing with $IDENTITY (hardened runtime + entitlements)"
        SIGN_OPTIONS=(--options runtime --timestamp)
    fi
    # The linker's own ad-hoc signature marks the dylibs "linker-signed", which a hardened
    # process refuses to load. Re-sign every nested library before the bundle.
    for framework in "$APP/Contents/Frameworks"/*.dylib; do
        codesign --force --sign "$IDENTITY" ${SIGN_OPTIONS[@]+"${SIGN_OPTIONS[@]}"} "$framework"
    done
    codesign --force --sign "$IDENTITY" \
        --entitlements packaging/Oreja.entitlements \
        ${SIGN_OPTIONS[@]+"${SIGN_OPTIONS[@]}"} \
        "$APP"
    codesign --verify --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'
else
    echo "==> Skipping signing"
fi

echo
echo "Built: $APP"
echo "Run:   open \"$APP\""
