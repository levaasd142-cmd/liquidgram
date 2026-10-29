#!/usr/bin/env bash
# Type-checks the UI test sources without a Mac: against stand-ins of UIKit and XCTest (UIKit.swift, XCTest.swift
# here) that have the signatures and the main-actor isolation of the iOS SDK, with a Linux Swift toolchain. It catches
# wrong names, labels, types and isolation before a CI run; only Xcode builds the tests for real. A stand-in lacks
# what no test has used yet: add it there with the SDK's signature.
#
# Usage: ios/LiquidgramUITests/Tools/typecheck/typecheck.sh [extra swiftc flags, such as -strict-concurrency=complete]
# Environment: SWIFTC, the swiftc to use (default: swiftc on the PATH)
set -euo pipefail

TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_DIR="$(cd "$TOOL_DIR/../../Sources" && pwd)"
SWIFTC="${SWIFTC:-swiftc}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/liquidgram-ui-typecheck.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

command -v "$SWIFTC" > /dev/null || { echo "error: no swiftc; set SWIFTC to a Swift toolchain's swiftc" >&2; exit 1; }

# Swift 5 language mode and minimal concurrency checking, as project.yml sets for the test target
SWIFT_FLAGS=(-swift-version 5 -parse-as-library)
"$SWIFTC" "${SWIFT_FLAGS[@]}" -emit-module -module-name UIKit \
  -emit-module-path "$WORK_DIR/UIKit.swiftmodule" "$TOOL_DIR/UIKit.swift"
"$SWIFTC" "${SWIFT_FLAGS[@]}" -emit-module -module-name XCTest -I "$WORK_DIR" \
  -emit-module-path "$WORK_DIR/XCTest.swiftmodule" "$TOOL_DIR/XCTest.swift"

# swift-corelibs-foundation lacks NSPredicate(format:), so a copy of the sources calls the stand-in's StubPredicate
mkdir -p "$WORK_DIR/sources"
for file in "$SOURCES_DIR"/*.swift; do
  sed 's/NSPredicate(/StubPredicate(/g' "$file" > "$WORK_DIR/sources/$(basename "$file")"
done
"$SWIFTC" "${SWIFT_FLAGS[@]}" -typecheck -module-name LiquidgramUITests -I "$WORK_DIR" "$@" "$WORK_DIR/sources"/*.swift
echo "Type-checked $(find "$SOURCES_DIR" -name '*.swift' | wc -l | tr -d ' ') files of $SOURCES_DIR"
