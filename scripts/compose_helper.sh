#!/usr/bin/env bash
set -euo pipefail

# --- Detect compose CLI ---
compose_bin() {
  if scripts/compose_helper.sh services/immich version >/dev/null 2>&1; then
    echo "docker compose"
  elif command -v scripts/compose_helper.sh services/immich >/dev/null 2>&1; then
    echo "docker-compose"
  else
    echo "❌ Neither 'docker compose' nor 'docker-compose' found in PATH." >&2
    echo "   Install Docker (CLI) or scripts/compose_helper.sh services/immich v2." >&2
    exit 127
  fi
}

# --- Usage ---
usage() {
  cat <<'USAGE'
Usage:
  compose_helper.sh <service_dir> <cmd> [args...]

Where:
  <service_dir>  folder containing docker-compose.yml (e.g., services/immich)
  <cmd>          up|down|restart|pull|build|ps|logs|exec|run|config

Examples:
  compose_helper.sh services/immich up -d
  compose_helper.sh services/immich logs -f server
  compose_helper.sh services/immich exec server bash
  compose_helper.sh services/immich ps

Notes:
- Prefers `docker compose`, falls back to `docker-compose`.
- Loads .env from <service_dir> if present.
- Sets a stable project name based on <service_dir> basename; override with PROJECT_NAME_OVERRIDE.
USAGE
}

# --- Args ---
if [[ $# -lt 2 ]]; then usage; exit 2; fi
SERVICE_DIR="$1"; shift
CMD="$1"; shift || true

if [[ ! -d "$SERVICE_DIR" ]]; then
  echo "❌ Service dir not found: $SERVICE_DIR" >&2; exit 1
fi
if [[ ! -f "$SERVICE_DIR/docker-compose.yml" && ! -f "$SERVICE_DIR/docker-compose.yaml" ]]; then
  echo "❌ No docker-compose.yml in $SERVICE_DIR" >&2; exit 1
fi

# --- Env & project settings ---
ABS_DIR="$(cd "$SERVICE_DIR" && pwd)"
PROJECT_NAME="${PROJECT_NAME_OVERRIDE:-$(basename "$ABS_DIR")}"
ENV_FILE_OPT=()
if [[ -f "$ABS_DIR/.env" ]]; then
  ENV_FILE_OPT=(--env-file "$ABS_DIR/.env")
fi

COMPOSE=$(compose_bin)

# --- Run ---
cd "$ABS_DIR"
case "$CMD" in
  up|down|restart|pull|build|ps|logs|config)
    exec $COMPOSE -p "$PROJECT_NAME" "${ENV_FILE_OPT[@]}" $CMD "$@"
    ;;
  exec|run)
    if [[ $# -lt 1 ]]; then
      echo "Usage: compose_helper.sh $SERVICE_DIR $CMD <service> [args...]" >&2
      exit 2
    fi
    exec $COMPOSE -p "$PROJECT_NAME" "${ENV_FILE_OPT[@]}" $CMD "$@"
    ;;
  *)
    usage; echo; echo "❌ Unknown cmd: $CMD" >&2; exit 2 ;;
esac
