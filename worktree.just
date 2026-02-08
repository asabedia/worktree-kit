# worktree.just — Importable justfile module for git worktree + docker isolation
# Import in your project's justfile:
#   import "path/to/worktree.just"
#
# Requires: just >= 1.19 (for source_directory)

set dotenv-load

# --- Configurable variables (override in your justfile) ---
wt-dir            := ".worktrees"
wt-max-slots      := "9"
wt-data-root      := ".docker-data"
wt-scripts        := source_directory() / "scripts"
wt-health-timeout := "60"             # seconds to wait for service health
wt-compose-file   := ""               # compose file path ("" = auto-detect)

# --- Docker commands with worktree isolation ---

# Start services with slot-aware ports
wt-up *args:
    #!/bin/bash
    set -e
    [ -f .env.local ] && set -a && . .env.local && set +a
    [ -n "{{wt-compose-file}}" ] && export WT_COMPOSE_FILE="{{wt-compose-file}}"
    SLOT="${WT_SLOT:-0}"
    eval $({{wt-scripts}}/wt-env.sh "$SLOT") 2>/dev/null || true
    if [ "$SLOT" != "0" ]; then
        export COMPOSE_PROJECT_NAME="$(basename "$(pwd)")-wt${SLOT}"
        echo "Slot $SLOT:"
        env | grep '^WT_' | sort || true
    fi
    docker compose ${WT_COMPOSE_FILE:+-f "$WT_COMPOSE_FILE"} up --build {{args}}

# Stop services
wt-down *args:
    #!/bin/bash
    set -e
    [ -f .env.local ] && set -a && . .env.local && set +a
    [ -n "{{wt-compose-file}}" ] && export WT_COMPOSE_FILE="{{wt-compose-file}}"
    SLOT="${WT_SLOT:-0}"
    eval $({{wt-scripts}}/wt-env.sh "$SLOT") 2>/dev/null || true
    if [ "$SLOT" != "0" ]; then
        export COMPOSE_PROJECT_NAME="$(basename "$(pwd)")-wt${SLOT}"
    fi
    docker compose ${WT_COMPOSE_FILE:+-f "$WT_COMPOSE_FILE"} down {{args}}

# Tail service logs
wt-logs *args:
    #!/bin/bash
    set -e
    [ -f .env.local ] && set -a && . .env.local && set +a
    [ -n "{{wt-compose-file}}" ] && export WT_COMPOSE_FILE="{{wt-compose-file}}"
    SLOT="${WT_SLOT:-0}"
    eval $({{wt-scripts}}/wt-env.sh "$SLOT") 2>/dev/null || true
    if [ "$SLOT" != "0" ]; then
        export COMPOSE_PROJECT_NAME="$(basename "$(pwd)")-wt${SLOT}"
    fi
    docker compose ${WT_COMPOSE_FILE:+-f "$WT_COMPOSE_FILE"} logs -f {{args}}

# Show current slot and computed ports
wt-status:
    #!/bin/bash
    [ -f .env.local ] && set -a && . .env.local && set +a
    [ -n "{{wt-compose-file}}" ] && export WT_COMPOSE_FILE="{{wt-compose-file}}"
    SLOT="${WT_SLOT:-0}"
    if [ "$SLOT" = "0" ]; then
        echo "Main repo (slot 0) — using default ports"
    else
        echo "Slot: $SLOT"
        export COMPOSE_PROJECT_NAME="$(basename "$(pwd)")-wt${SLOT}"
    fi
    eval $({{wt-scripts}}/wt-env.sh "$SLOT") 2>/dev/null || true
    env | grep '^WT_' | sort || echo "(no wt.* labels found)"
    echo ""
    echo "Active slots:"
    MAIN_ROOT="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"
    {{wt-scripts}}/wt-slot.sh list "$MAIN_ROOT/{{wt-dir}}"

# --- Worktree lifecycle ---

# Create new worktree
wt-new branch base="main":
    #!/bin/bash
    set -e
    export WT_MAX_SLOTS={{wt-max-slots}}
    git fetch origin {{base}} --quiet
    mkdir -p {{wt-dir}}
    WT_PATH="{{wt-dir}}/{{branch}}"
    git worktree add "$WT_PATH" -b {{branch}} origin/{{base}}
    {{wt-scripts}}/wt-setup.sh "{{wt-dir}}" "$WT_PATH" "{{branch}}"
    echo ""
    echo "Ready: cd {{wt-dir}}/{{branch}}"

# Remove worktree by branch name
wt-rm branch:
    #!/bin/bash
    set -e
    WT_PATH="{{wt-dir}}/{{branch}}"
    # Get slot before removing
    SLOT=""
    if [ -f "$WT_PATH/.env.local" ]; then
        SLOT=$(grep '^WT_SLOT=' "$WT_PATH/.env.local" 2>/dev/null | tail -1 | cut -d= -f2)
    fi
    git worktree remove "$WT_PATH" --force
    git branch -d {{branch}} 2>/dev/null || git branch -D {{branch}}
    # Release slot
    if [ -n "$SLOT" ] && [ "$SLOT" != "0" ]; then
        {{wt-scripts}}/wt-slot.sh release "{{wt-dir}}" "$SLOT"
        echo "Released slot $SLOT"
        # Offer to clean data
        DATA_DIR="{{wt-data-root}}/slot-$SLOT"
        if [ -d "$DATA_DIR" ]; then
            read -p "Delete docker data ($DATA_DIR)? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -rf "$DATA_DIR"
                echo "Deleted $DATA_DIR"
            fi
        fi
    fi

# List worktrees with slot info
wt-list:
    #!/bin/bash
    echo "=== Git Worktrees ==="
    git worktree list
    echo ""
    echo "=== Slot Assignments ==="
    MAIN_ROOT="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"
    {{wt-scripts}}/wt-slot.sh list "$MAIN_ROOT/{{wt-dir}}"

# Prune stale worktrees
wt-prune:
    git worktree prune -v

# Print worktree path (use with: cd $(just wt-cd branch))
wt-cd branch:
    @echo "{{wt-dir}}/{{branch}}"

# Create worktree + start Docker services (agent-ready)
wt-dev branch base="main":
    #!/bin/bash
    set -e
    # 1. Check system requirements
    [ -n "{{wt-compose-file}}" ] && export WT_COMPOSE_FILE="{{wt-compose-file}}"
    {{wt-scripts}}/wt-doctor.sh "."
    # 2. Create worktree (same as wt-new)
    export WT_MAX_SLOTS={{wt-max-slots}}
    git fetch origin {{base}} --quiet
    mkdir -p {{wt-dir}}
    WT_PATH="{{wt-dir}}/{{branch}}"
    git worktree add "$WT_PATH" -b {{branch}} origin/{{base}}
    {{wt-scripts}}/wt-setup.sh "{{wt-dir}}" "$WT_PATH" "{{branch}}"
    # 3. Docker bootstrap
    echo ""
    echo "Starting Docker services..."
    cd "$WT_PATH"
    {{wt-scripts}}/wt-docker-ready.sh {{wt-health-timeout}} full
    echo ""
    echo "Ready: cd {{wt-dir}}/{{branch}}"

# Check health of Docker services in current worktree
wt-health:
    #!/bin/bash
    set -e
    [ -f .env.local ] && set -a && . .env.local && set +a
    [ -n "{{wt-compose-file}}" ] && export WT_COMPOSE_FILE="{{wt-compose-file}}"
    SLOT="${WT_SLOT:-0}"
    if [ "$SLOT" != "0" ]; then
        export COMPOSE_PROJECT_NAME="$(basename "$(pwd)")-wt${SLOT}"
    fi
    {{wt-scripts}}/wt-docker-ready.sh {{wt-health-timeout}} check

# Remove merged worktrees
wt-clean:
    #!/bin/bash
    for wt in {{wt-dir}}/*/; do
        [ -d "$wt" ] || continue
        branch=$(basename "$wt")
        if git branch --merged main | grep -q "$branch"; then
            echo "Removing merged worktree: $branch"
            # Get slot
            SLOT=""
            if [ -f "$wt/.env.local" ]; then
                SLOT=$(grep '^WT_SLOT=' "$wt/.env.local" 2>/dev/null | tail -1 | cut -d= -f2)
            fi
            git worktree remove "$wt" 2>/dev/null || true
            git branch -d "$branch" 2>/dev/null || true
            if [ -n "$SLOT" ] && [ "$SLOT" != "0" ]; then
                {{wt-scripts}}/wt-slot.sh release "{{wt-dir}}" "$SLOT"
                echo "Released slot $SLOT"
            fi
        fi
    done
    git worktree prune
