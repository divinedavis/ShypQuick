#!/usr/bin/env bash
#
# ShypQuick — full test sweep.
#
# Runs the XCTest unit suite (PricingServiceTests, etc.) and the
# XCUITest end-to-end suite (PricingFlowUITests). Both must pass
# before TestFlight ship.
#
# Usage:
#   ./scripts/run_tests.sh             # full sweep
#   ./scripts/run_tests.sh unit        # unit tests only
#   ./scripts/run_tests.sh ui          # UI tests only
#

set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="ShypQuick.xcodeproj"
SCHEME="ShypQuick"
# iCloud-synced ~/Desktop adds FinderInfo xattrs that break codesign on
# the simulator .xctest bundle. Build under /tmp instead.
DERIVED="/tmp/shypquick-derived"

mode="${1:-all}"

# Pick a booted simulator if any, otherwise the first available iPhone.
SIMULATOR_ID="${SIMULATOR_ID:-}"
if [[ -z "$SIMULATOR_ID" ]]; then
    SIMULATOR_ID=$(xcrun simctl list devices booted -j 2>/dev/null \
        | python3 -c "import json,sys;d=json.load(sys.stdin);print(next(iter([dev['udid'] for runtime in d['devices'].values() for dev in runtime if dev.get('state')=='Booted']), ''))" 2>/dev/null || echo "")
fi
if [[ -z "$SIMULATOR_ID" ]]; then
    SIMULATOR_ID=$(xcrun simctl list devices available -j \
        | python3 -c "
import json,sys
d=json.load(sys.stdin)
for runtime in d['devices'].values():
    for dev in runtime:
        if 'iPhone' in dev.get('name','') and dev.get('isAvailable'):
            print(dev['udid']); sys.exit(0)
")
fi
if [[ -z "$SIMULATOR_ID" ]]; then
    echo "error: no iPhone simulator available" >&2
    exit 1
fi
echo "==> using simulator $SIMULATOR_ID"

run() {
    local only="$1"
    xcodebuild test \
        -project "$PROJECT" \
        -scheme  "$SCHEME" \
        -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
        -derivedDataPath "$DERIVED" \
        -only-testing:"$only"
}

run_all() {
    # Single xcodebuild invocation runs every Testable on the scheme:
    # PricingServiceTests + PricingServicePerformanceTests +
    # PricingServiceSwiftTests (Swift Testing) + PricingFlowUITests.
    # One process keeps the simulator + build state warm and avoids a
    # back-to-back race where the second invocation finds the sim busy.
    xcodebuild test \
        -project "$PROJECT" \
        -scheme  "$SCHEME" \
        -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
        -derivedDataPath "$DERIVED"
}

case "$mode" in
    unit) run ShypQuickTests ;;
    ui)   run ShypQuickUITests ;;
    all)  run_all ;;
    *)
        echo "usage: $0 [unit|ui|all]" >&2
        exit 2
        ;;
esac
echo "==> all requested tests passed"
