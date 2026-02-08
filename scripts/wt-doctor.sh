#!/bin/bash
# wt-doctor.sh — Check system requirements before worktree setup
# Usage: wt-doctor.sh [project-dir]
#
# Checks: git, just, docker, docker compose, jq (optional)
# If .wt-required-tools exists: checks each listed tool

set -euo pipefail

PROJECT_DIR="${1:-.}"
MISSING=0

check() {
    local tool="$1" required="${2:-true}"
    if command -v "$tool" &>/dev/null; then
        printf "  %-20s ok\n" "$tool"
    elif [ "$required" = "true" ]; then
        printf "  %-20s MISSING\n" "$tool"
        MISSING=1
    else
        printf "  %-20s MISSING (optional)\n" "$tool"
    fi
}

echo "Checking requirements..."

# Always required
check git
check just

# Docker tools
check docker
if command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
    printf "  %-20s ok\n" "docker compose"
else
    printf "  %-20s MISSING\n" "docker compose"
    MISSING=1
fi
check jq false

# Require a compose file
COMPOSE_FILE=""
for f in "$PROJECT_DIR/docker-compose.yml" "$PROJECT_DIR/compose.yml"; do
    [ -f "$f" ] && COMPOSE_FILE="$f" && break
done
if [ -z "$COMPOSE_FILE" ]; then
    printf "  %-20s MISSING\n" "compose file"
    MISSING=1
else
    printf "  %-20s ok\n" "compose file"
fi

# Project-specific tools from .wt-required-tools
TOOLS_FILE="$PROJECT_DIR/.wt-required-tools"
if [ -f "$TOOLS_FILE" ]; then
    while IFS= read -r line; do
        line="${line%%#*}"        # strip comments
        line="${line// /}"        # strip spaces
        [ -z "$line" ] && continue
        check "$line"
    done < "$TOOLS_FILE"
fi

if [ "$MISSING" -ne 0 ]; then
    echo ""
    echo "Install missing tools before continuing."
    exit 1
fi

echo "All checks passed."
