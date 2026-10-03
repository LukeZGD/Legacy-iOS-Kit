#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# macOS entry point for a complete, experimental custom-IPSW restore.
cd "$(dirname "$0")" || exit 1
./restore.sh --jailbreak --touch4-hardware-fixes --no-version-check "$@"
result=$?
if [[ $result != 0 ]]; then
    echo "Legacy iOS Kit exited with status $result. Press Return to close."
    read -r
fi
exit "$result"
