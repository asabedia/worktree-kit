#!/bin/bash
# wt-setup.sh — Post-creation orchestrator for new worktrees
# Usage: wt-setup.sh <wt-dir> <worktree-path> <branch>
#
# Sequence:
# 1. Allocate slot
# 2. Copy .env.local from main repo
# 3. Append WT_SLOT to worktree .env.local
# 4. Warn if wt-dir not in .gitignore
# 5. Install deps
# 6. Run project hook (scripts/wt-post-setup.sh) if exists
# 7. Display port summary

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WT_DIR="${1:?Usage: wt-setup.sh <wt-dir> <worktree-path> <branch>}"
WT_PATH="${2:?Usage: wt-setup.sh <wt-dir> <worktree-path> <branch>}"
BRANCH="${3:?Usage: wt-setup.sh <wt-dir> <worktree-path> <branch>}"

PROJECT_ROOT="$(git rev-parse --show-toplevel)"

# 1. Allocate slot
SLOT=$("$SCRIPT_DIR/wt-slot.sh" allocate "$WT_DIR" "$BRANCH")
echo "Allocated slot $SLOT"

# 2. Copy .env.local from main repo (if exists and not already present)
if [ -f "$PROJECT_ROOT/.env.local" ] && [ ! -f "$WT_PATH/.env.local" ]; then
    cp "$PROJECT_ROOT/.env.local" "$WT_PATH/.env.local"
fi

# 3. Append WT_SLOT
[ -f "$WT_PATH/.env.local" ] || touch "$WT_PATH/.env.local"
echo "WT_SLOT=$SLOT" >> "$WT_PATH/.env.local"

# 4. Warn if wt-dir not in .gitignore
if ! git check-ignore -q "$WT_DIR" 2>/dev/null; then
    echo "Warning: $WT_DIR is not in .gitignore — add it to avoid committing worktrees"
fi

# 5. Install deps
"$SCRIPT_DIR/wt-deps.sh" "$WT_PATH"

# 6. Run project hook if exists
HOOK="$WT_PATH/scripts/wt-post-setup.sh"
if [ -x "$HOOK" ]; then
    echo "Running project hook: scripts/wt-post-setup.sh"
    (cd "$WT_PATH" && ./scripts/wt-post-setup.sh)
fi

# 7. Display port summary
echo ""
echo "--- Port Summary (slot $SLOT) ---"
eval "$("$SCRIPT_DIR/wt-env.sh" "$SLOT")" 2>/dev/null || true
env | grep '^WT_' | sort || echo "(no wt.* labels found in docker-compose.yml)"
echo "---"
