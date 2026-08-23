#!/bin/bash
# Phase gate: regenerate project, build, and test on iPhone 17 Pro simulator.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project RCF.xcodeproj -scheme RCF \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build test 2>&1 | xcbeautify --quiet || xcodebuild -project RCF.xcodeproj -scheme RCF \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build test
