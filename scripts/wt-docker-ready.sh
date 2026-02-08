#!/bin/bash
# wt-docker-ready.sh — Docker bootstrap + health check
# Usage: wt-docker-ready.sh [timeout] [mode]
#   timeout: seconds to wait for health (default 60)
#   mode: "full" (pull+start+health) or "check" (health only)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TIMEOUT="${1:-60}"
MODE="${2:-full}"

# Find compose file
COMPOSE_FILE=""
for f in docker-compose.yml compose.yml; do
    [ -f "$f" ] && COMPOSE_FILE="$f" && break
done

if [ -z "$COMPOSE_FILE" ]; then
    echo "Error: No compose file found (docker-compose.yml or compose.yml)."
    exit 1
fi

# Source env and compute port vars
[ -f .env.local ] && set -a && . .env.local && set +a
SLOT="${WT_SLOT:-0}"
eval $("$SCRIPT_DIR/wt-env.sh" "$SLOT" "$COMPOSE_FILE") 2>/dev/null || true

# TCP probe — bash /dev/tcp with python3 fallback
tcp_probe() {
    local host="$1" port="$2"
    (echo >/dev/tcp/"$host"/"$port") 2>/dev/null && return 0
    python3 -c "
import socket, sys
s = socket.socket()
s.settimeout(2)
try:
    s.connect(('$host', $port))
    s.close()
except:
    sys.exit(1)
" 2>/dev/null && return 0
    return 1
}

# Full mode: pull + start
if [ "$MODE" = "full" ]; then
    echo "Pulling images..."
    docker compose -f "$COMPOSE_FILE" pull --quiet 2>/dev/null || true
    echo "Starting services..."
    docker compose -f "$COMPOSE_FILE" up -d --build
    echo ""
fi

# Collect WT_*_PORT vars
declare -a PORT_NAMES=()
declare -a PORT_VALS=()
while IFS='=' read -r name val; do
    if [[ "$name" =~ ^WT_.*_PORT$ ]]; then
        PORT_NAMES+=("$name")
        PORT_VALS+=("$val")
    fi
done < <(env | sort)

if [ ${#PORT_NAMES[@]} -eq 0 ]; then
    echo "No WT_*_PORT vars found — nothing to health-check."
    exit 0
fi

echo "Waiting for services (timeout ${TIMEOUT}s)..."
DEADLINE=$((SECONDS + TIMEOUT))
declare -A READY=()

while [ $SECONDS -lt $DEADLINE ]; do
    ALL_UP=true
    for i in "${!PORT_NAMES[@]}"; do
        name="${PORT_NAMES[$i]}"
        [ "${READY[$name]:-}" = "1" ] && continue
        port="${PORT_VALS[$i]}"
        if tcp_probe localhost "$port"; then
            READY["$name"]=1
            printf "  %-25s :%s  ok\n" "$name" "$port"
        else
            ALL_UP=false
        fi
    done
    $ALL_UP && break
    sleep 2
done

echo ""

# Final status
FAILED=0
for i in "${!PORT_NAMES[@]}"; do
    name="${PORT_NAMES[$i]}"
    port="${PORT_VALS[$i]}"
    if [ "${READY[$name]:-}" != "1" ]; then
        printf "  %-25s :%s  TIMEOUT\n" "$name" "$port"
        FAILED=1
    fi
done

if [ "$FAILED" -ne 0 ]; then
    echo "Some services failed to start within ${TIMEOUT}s."
    exit 1
fi

echo "All services responding."
