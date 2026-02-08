#!/bin/bash
# wt-deps.sh — Auto-detect and install project dependencies
# Usage: wt-deps.sh [directory]
#
# Supports: Node (npm/pnpm/yarn/bun), Python (pip/poetry/uv), Go, Rust, JVM (Gradle/Maven)

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

# --- JVM (Gradle/Maven) ---
if [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
    echo "Installing JVM deps (Gradle)..."
    if [ -f "./gradlew" ]; then
        ./gradlew dependencies -q 2>/dev/null || ./gradlew build --dry-run -q
    else
        gradle dependencies -q 2>/dev/null || gradle build --dry-run -q
    fi
    installed=1
elif [ -f "pom.xml" ]; then
    echo "Installing JVM deps (Maven)..."
    if [ -f "./mvnw" ]; then
        ./mvnw dependency:resolve -q
    else
        mvn dependency:resolve -q
    fi
    installed=1
fi

# --- Subdirectory scan (monorepo) ---
if [ "${WT_DEPS_NO_RECURSE:-}" != "1" ]; then
    export WT_DEPS_NO_RECURSE=1
    for dir in */; do
        [ -d "$dir" ] || continue
        if [ -f "$dir/package.json" ] || [ -f "$dir/build.gradle" ] || [ -f "$dir/build.gradle.kts" ] || [ -f "$dir/pom.xml" ] || [ -f "$dir/go.mod" ] || [ -f "$dir/Cargo.toml" ]; then
            echo ""
            echo "Found deps in $dir — running wt-deps..."
            "$0" "$dir"
        fi
    done
fi

if [ "$installed" = "0" ]; then
    echo "No recognized dependency files found."
fi
