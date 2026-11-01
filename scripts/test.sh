#!/bin/bash
# Runs the Oreja test suite.
#
# The suite is a normal Swift executable because this machine has no XCTest runtime (Command Line
# Tools only). It covers the coordinator state machine, the activity detector, settings, the Apple
# Music error mapping and the stale-pause recovery rules.
#
#   ./scripts/test.sh                 # all tests
#   ./scripts/test.sh resume          # only tests whose name contains "resume"

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUILD="$ROOT/build"
MODULES="$BUILD/modules"
LIB="$BUILD/lib"
SDK="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"
TARGET="$ARCH-apple-macosx14.2"
SWIFT_FLAGS=(-swift-version 6 -target "$TARGET" -sdk "$SDK" -g)
LINK_FLAGS=(-I "$MODULES" -L "$LIB")

mkdir -p "$MODULES" "$LIB" "$BUILD/bin"

build_module() {
    local name="$1"
    local extra_link=("${@:2}")
    local sources=()
    while IFS= read -r file; do sources+=("$file"); done < <(find "packages/$name/Sources" -name '*.swift' | sort)
    swiftc "${SWIFT_FLAGS[@]}" -parse-as-library \
        -module-name "$name" \
        -emit-module -emit-library \
        -emit-module-path "$MODULES/$name.swiftmodule" \
        -o "$LIB/lib$name.dylib" \
        "${LINK_FLAGS[@]}" ${extra_link[@]+"${extra_link[@]}"} \
        "${sources[@]}"
}

echo "==> Building modules"
build_module OrejaCore
build_module OrejaAudio -lOrejaCore
build_module OrejaMedia -lOrejaCore

echo "==> Building test runner"
TEST_SOURCES=()
while IFS= read -r file; do TEST_SOURCES+=("$file"); done < <(find Tests/OrejaTestRunner -name '*.swift' | sort)
swiftc "${SWIFT_FLAGS[@]}" -parse-as-library \
    "${LINK_FLAGS[@]}" -lOrejaCore -lOrejaAudio -lOrejaMedia \
    -Xlinker -rpath -Xlinker "$LIB" \
    -o "$BUILD/bin/oreja-tests" \
    "${TEST_SOURCES[@]}"

echo "==> Running"
"$BUILD/bin/oreja-tests" "$@"
