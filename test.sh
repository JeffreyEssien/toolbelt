#!/bin/bash
# Runs the unit tests. The Command Line Tools keep the Swift Testing macro
# plugin in a subfolder that `swift test` doesn't search by default.
set -euo pipefail
cd "$(dirname "$0")"
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing "$@"
