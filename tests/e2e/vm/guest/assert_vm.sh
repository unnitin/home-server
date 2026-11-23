#!/usr/bin/env bash
# Refuse to continue unless running inside a virtual machine.
# Sourced first by every guest script that touches disks or system settings,
# so none of them can ever run on the real Mac mini by mistake.
set -euo pipefail

if [[ "$(sysctl -n kern.hv_vmm_present 2>/dev/null || echo 0)" != "1" ]]; then
    echo "[ERROR] refusing: this is not a virtual machine (kern.hv_vmm_present != 1)" >&2
    exit 3
fi
