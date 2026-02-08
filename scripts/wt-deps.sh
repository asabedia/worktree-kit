#!/bin/bash
# wt-deps.sh — Auto-detect and install project dependencies
# Usage: wt-deps.sh [directory]
#
# Supports: Node (npm/pnpm/yarn/bun), Python (pip/poetry/uv), Go, Rust

set -euo pipefail

DIR="${1:-.}"
cd "$DIR"

installed=0

# --- Node.js ---
if [ -f "package.json" ]; then
    if [ -f "bun.lockb" ] || [ -f "bun.lock" ]; then
        echo "Installing Node deps (bun)..."
        bun install
    elif [ -f "pnpm-lock.yaml" ]; then
        echo "Installing Node deps (pnpm)..."
        pnpm install
    elif [ -f "yarn.lock" ]; then
        echo "Installing Node deps (yarn)..."
        yarn install
    else
        echo "Installing Node deps (npm)..."
        npm install
    fi
    installed=1
fi

# --- Python ---
# Check for poetry/uv project first (pyproject.toml)
if [ -f "pyproject.toml" ]; then
    if command -v poetry &>/dev/null && grep -q '\[tool\.poetry\]' pyproject.toml 2>/dev/null; then
        echo "Installing Python deps (poetry)..."
        poetry install
        installed=1
    elif command -v uv &>/dev/null; then
        echo "Installing Python deps (uv)..."
        uv sync
        installed=1
    elif [ -f "requirements.txt" ]; then
        echo "Installing Python deps (pip)..."
        pip install -r requirements.txt
        installed=1
    fi
fi

# requirements.txt — scan root and one level deep
if [ "$installed" = "0" ] || [ -f "requirements.txt" ]; then
    for req in requirements.txt */requirements.txt; do
        if [ -f "$req" ]; then
            echo "Installing Python deps from $req (pip)..."
            pip install -r "$req"
            installed=1
        fi
    done
fi

# --- Go ---
if [ -f "go.mod" ]; then
    echo "Downloading Go modules..."
    go mod download
    installed=1
fi

# --- Rust ---
if [ -f "Cargo.toml" ]; then
    echo "Fetching Rust crates..."
    cargo fetch
    installed=1
fi

if [ "$installed" = "0" ]; then
    echo "No recognized dependency files found."
fi
