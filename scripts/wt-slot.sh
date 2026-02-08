#!/bin/bash
# wt-slot.sh — Slot allocator for worktree isolation
# Usage: wt-slot.sh <command> <wt-dir> [args...]
#
# Commands:
#   allocate <wt-dir> <branch>       — reserve next free slot, print number
#   release  <wt-dir> <slot>         — free a slot
#   list     <wt-dir>                — show slot → branch mapping
#   get      <wt-dir> <worktree-path> — print slot for a worktree

set -euo pipefail

MAX_SLOTS="${WT_MAX_SLOTS:-9}"

cmd="${1:-}"
wt_dir="${2:-}"

if [ -z "$cmd" ] || [ -z "$wt_dir" ]; then
    echo "Usage: wt-slot.sh <allocate|release|list|get> <wt-dir> [args...]" >&2
    exit 1
fi

mkdir -p "$wt_dir"

case "$cmd" in
    allocate)
        branch="${3:?allocate requires branch name}"
        for i in $(seq 1 "$MAX_SLOTS"); do
            slot_file="$wt_dir/.slot-$i"
            if [ ! -f "$slot_file" ]; then
                echo "$branch" > "$slot_file"
                echo "$i"
                exit 0
            fi
        done
        echo "Error: All $MAX_SLOTS slots in use. Remove a worktree first." >&2
        exit 1
        ;;

    release)
        slot="${3:?release requires slot number}"
        rm -f "$wt_dir/.slot-$slot"
        ;;

    list)
        found=0
        for i in $(seq 1 "$MAX_SLOTS"); do
            slot_file="$wt_dir/.slot-$i"
            if [ -f "$slot_file" ]; then
                branch=$(cat "$slot_file")
                printf "slot %d → %s\n" "$i" "$branch"
                found=1
            fi
        done
        if [ "$found" = "0" ]; then
            echo "No active slots."
        fi
        ;;

    get)
        wt_path="${3:?get requires worktree path}"
        env_file="$wt_path/.env.local"
        if [ -f "$env_file" ]; then
            slot=$(grep '^WT_SLOT=' "$env_file" 2>/dev/null | tail -1 | cut -d= -f2)
            if [ -n "$slot" ]; then
                echo "$slot"
                exit 0
            fi
        fi
        echo "Error: No slot found for $wt_path" >&2
        exit 1
        ;;

    *)
        echo "Unknown command: $cmd" >&2
        echo "Usage: wt-slot.sh <allocate|release|list|get> <wt-dir> [args...]" >&2
        exit 1
        ;;
esac
