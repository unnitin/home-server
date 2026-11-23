#!/usr/bin/env bash
# Prove the VM's faststore completes real I/O: write 256 MB, flush, read it
# back, delete it. Runs INSIDE the VM.
#
#   io_smoke.sh [DIR]     (default /Volumes/faststore)
#
# Exits 0 when done. A wedged volume never returns, so callers run it with a
# time limit (tart_exec 300 ...). Found the hard way: an AppleRAID mirror in a
# macOS VM accepts writes, then deadlocks on the first flush.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=assert_vm.sh
source "$HERE/assert_vm.sh"

DIR="${1:-/Volumes/faststore}"
F="$DIR/.io-smoke-$$"
start=$(date +%s)
trap 'rm -f "$F"' EXIT
dd if=/dev/urandom of="$F" bs=1m count=256 2>/dev/null
sync
cat "$F" >/dev/null
rm -f "$F"
sync
echo "[INFO]  faststore I/O smoke test passed in $(($(date +%s) - start))s ($DIR)"
