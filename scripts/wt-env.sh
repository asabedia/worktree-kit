#!/bin/bash
# wt-env.sh — Parse docker-compose wt.* labels into env var exports
# Usage: eval $(wt-env.sh <slot> [compose-file])
#
# Reads wt.base-port and wt.data-dir labels from compose services.
# Outputs: export WT_{SERVICE}_PORT=N  and  export WT_{SERVICE}_DATA=path
#
# Service naming: foo-bar → WT_FOO_BAR_PORT (uppercase, hyphens to underscores)

set -euo pipefail

SLOT="${1:-0}"
COMPOSE_FILE="${2:-docker-compose.yml}"
DATA_ROOT="${WT_DATA_ROOT:-.docker-data}"

if [ ! -f "$COMPOSE_FILE" ]; then
    exit 0
fi

# Normalize service name: uppercase, hyphens/dots to underscores
normalize_name() {
    echo "$1" | tr '[:lower:]' '[:upper:]' | tr '-.' '__'
}

# Compute data path for a service
data_path() {
    local service="$1" data_dir="$2"
    if [ "$SLOT" = "0" ]; then
        echo "$DATA_ROOT/$service/"
    else
        echo "$DATA_ROOT/slot-$SLOT/$service/"
    fi
}

# Try docker compose config + jq (accurate YAML parsing)
try_compose_jq() {
    if ! command -v jq &>/dev/null; then
        return 1
    fi
    if ! command -v docker &>/dev/null; then
        return 1
    fi

    local json
    json=$(docker compose -f "$COMPOSE_FILE" config --format json --no-interpolate 2>/dev/null) || return 1

    echo "$json" | jq -r --arg slot "$SLOT" --arg data_root "$DATA_ROOT" '
        .services // {} | to_entries[] |
        select(.value.labels != null) |
        . as $svc |
        (.key | ascii_upcase | gsub("-"; "_") | gsub("\\."; "_")) as $name |
        (
            if (.value.labels | type) == "object" then
                .value.labels
            else
                # array format: ["key=value", ...]
                .value.labels | map(split("=") | {(.[0]): .[1:] | join("=")}) | add // {}
            end
        ) as $labels |
        (
            if $labels["wt.base-port"] then
                if ($slot | tonumber) == 0 then
                    "export WT_\($name)_PORT=\($labels["wt.base-port"])"
                else
                    "export WT_\($name)_PORT=\(($labels["wt.base-port"] | tonumber) + ($slot | tonumber))"
                end
            else empty end
        ),
        (
            if $labels["wt.data-dir"] then
                if ($slot | tonumber) == 0 then
                    "export WT_\($name)_DATA=\($data_root)/\($svc.key)/"
                else
                    "export WT_\($name)_DATA=\($data_root)/slot-\($slot)/\($svc.key)/"
                end
            else empty end
        )
    ' 2>/dev/null
}

# Fallback: grep/sed state machine (no deps beyond bash)
try_grep_fallback() {
    local current_service="" in_labels=0

    while IFS= read -r line; do
        # Strip comments
        line="${line%%#*}"

        # Detect service name (top-level key under services:)
        if echo "$line" | grep -qE '^  [a-zA-Z]'; then
            if echo "$line" | grep -qE '^  [a-zA-Z][a-zA-Z0-9_-]*:'; then
                current_service=$(echo "$line" | sed 's/^  //;s/:.*//')
                in_labels=0
            fi
        fi

        # Detect labels section
        if echo "$line" | grep -qE '^\s+labels:'; then
            in_labels=1
            continue
        fi

        # If in labels, look for wt.* entries
        if [ "$in_labels" = "1" ] && [ -n "$current_service" ]; then
            # Exit labels on non-indented or differently-indented line
            if echo "$line" | grep -qE '^\s{4}[a-z]' && ! echo "$line" | grep -qE '^\s{6}'; then
                in_labels=0
                continue
            fi

            local base_port="" data_dir=""
            if echo "$line" | grep -q 'wt\.base-port'; then
                base_port=$(echo "$line" | sed 's/.*wt\.base-port[":]*\s*//;s/[" ]*$//')
                base_port=$(echo "$base_port" | tr -d '"' | tr -d "'")
                if [ -n "$base_port" ]; then
                    local name
                    name=$(normalize_name "$current_service")
                    if [ "$SLOT" = "0" ]; then
                        echo "export WT_${name}_PORT=$base_port"
                    else
                        echo "export WT_${name}_PORT=$((base_port + SLOT))"
                    fi
                fi
            fi
            if echo "$line" | grep -q 'wt\.data-dir'; then
                data_dir=$(echo "$line" | sed 's/.*wt\.data-dir[":]*\s*//;s/[" ]*$//')
                data_dir=$(echo "$data_dir" | tr -d '"' | tr -d "'")
                if [ -n "$data_dir" ]; then
                    local name
                    name=$(normalize_name "$current_service")
                    echo "export WT_${name}_DATA=$(data_path "$current_service" "$data_dir")"
                fi
            fi
        fi
    done < "$COMPOSE_FILE"
}

# Try jq path first, fall back to grep
output=$(try_compose_jq 2>/dev/null) || output=""

if [ -z "$output" ]; then
    output=$(try_grep_fallback)
fi

if [ -n "$output" ]; then
    echo "$output"
fi
