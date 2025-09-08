#!/usr/bin/env bash
set -euo pipefail
brew install colima docker scripts/compose_helper.sh services/immich echo "Colima and Docker installed."
