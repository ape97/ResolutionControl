#!/bin/zsh
# Checks Resolution Control (scripts/check.sh), installs it to /Applications and relaunches it.
# Installs only if the checks are green. Afterwards prints status and an idle measurement as proof.
set -euo pipefail
cd "${0:A:h}/.."

./scripts/check.sh || { print "Not installed: checks failed."; exit 1 }

TARGET="/Applications/ResolutionControl.app"
pkill -x ResolutionControl 2>/dev/null && sleep 0.5 || true
rm -rf "$TARGET"
ditto build/Build/Products/Release/ResolutionControl.app "$TARGET"
open -g "$TARGET"
sleep 2
print "\nResolution Control installed: $TARGET"
./scripts/status.sh
./scripts/idle.sh 60
