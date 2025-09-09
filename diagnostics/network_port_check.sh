#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/diag_lib.sh"

HOST="${1:-localhost}"
PORT="${2:-2283}"

section "Network Port Check - $HOST:$PORT"

# Determine service name based on common ports
case "$PORT" in
    2283) service_name="Immich Photo Service" ;;
    32400) service_name="Plex Media Server" ;;
    8443) service_name="Caddy Reverse Proxy" ;;
    22) service_name="SSH" ;;
    80) service_name="HTTP" ;;
    443) service_name="HTTPS" ;;
    *) service_name="Unknown Service" ;;
esac

ok "Testing: $service_name on $HOST:$PORT"

# Check if netcat is available
if ! command -v nc >/dev/null 2>&1; then
    fail "netcat (nc) not available - cannot test port connectivity"
    print_summary
    exit 1
fi

# Test TCP connectivity
if nc -z "$HOST" "$PORT" 2>/dev/null; then
    ok "Port $PORT is open on $HOST"
    
    # For HTTP services, try a basic HTTP probe
    case "$PORT" in
        2283|32400|8443|80|443)
            if [[ "$HOST" == "localhost" || "$HOST" == "127.0.0.1" ]]; then
                if [[ "$PORT" == "443" ]]; then
                    # HTTPS port
                    if command -v curl >/dev/null 2>&1; then
                        if curl -fsSk -m 3 "https://$HOST:$PORT" >/dev/null 2>&1; then
                            ok "HTTPS service responding on port $PORT"
                        else
                            warn "Port $PORT open but HTTPS service not responding"
                        fi
                    fi
                else
                    # HTTP port
                    if command -v curl >/dev/null 2>&1; then
                        if curl -fsS -m 3 "http://$HOST:$PORT" >/dev/null 2>&1; then
                            ok "HTTP service responding on port $PORT"
                        else
                            warn "Port $PORT open but HTTP service not responding"
                        fi
                    fi
                fi
            fi
            ;;
    esac
else
    fail "Port $PORT is closed or filtered on $HOST"
    
    # Provide helpful suggestions based on port
    case "$PORT" in
        2283)
            echo "  💡 Suggestions:"
            echo "     - Check if Immich containers are running: ./diagnostics/check_docker_services.sh"
            echo "     - Start Immich: cd services/immich && docker compose up -d"
            ;;
        32400)
            echo "  💡 Suggestions:"
            echo "     - Check if Plex is running: ./diagnostics/check_plex_native.sh"
            echo "     - Start Plex: open -a 'Plex Media Server'"
            ;;
        8443)
            echo "  💡 Suggestions:"
            echo "     - Check if Caddy is running: brew services list | grep caddy"
            echo "     - Start Caddy: brew services start caddy"
            ;;
    esac
fi

print_summary