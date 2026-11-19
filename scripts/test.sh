#!/bin/bash
# Runs the swift-testing suite. Command Line Tools keep Testing.framework outside SwiftPM's search
# paths and ship a broken _Testing_Foundation overlay, so both are handled here (see ADR-0001).
set -euo pipefail
cd "$(dirname "$0")/.."

frameworks="$(xcode-select -p)/Library/Developer/Frameworks"
args=()
if [[ -d "$frameworks/Testing.framework" ]]; then
    args=(-Xswiftc -F -Xswiftc "$frameworks"
          -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays
          -Xlinker -rpath -Xlinker "$frameworks")
fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT
swift test ${args[@]+"${args[@]}"} "$@" 2>&1 | tee "$log"
# SwiftPM reports success when it silently finds no tests, so a passing run must also have run tests.
grep -qE "Test run with [1-9][0-9]* tests? .*passed" "$log" || { echo "test.sh: no tests ran" >&2; exit 1; }
