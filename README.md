# worktree-kit

Run parallel feature branches with isolated Docker ports and data — zero config conflicts.

**The problem:** You're working on `feature/auth` with `docker compose up`, then need to context-switch to `feature/payments`. You either tear down your stack or get port conflicts. With worktree-kit, each branch gets its own worktree with automatically offset ports and isolated data directories.

## Quickstart

**Using Claude Code** (recommended — generates everything for you):

```bash
# Install the plugin
/plugin marketplace add asabedia/worktree-kit
/plugin install worktree-kit-onboard@worktree-kit

# From your project repo, run the onboarding wizard
/wt-onboard
```

The wizard scans your project, asks a few questions, and generates your `docker-compose.yml`, `justfile`, Dockerfiles, and hot-reload configs.

**Manual setup** (4 steps):

```bash
# 1. Add to your project
git submodule add https://github.com/asabedia/worktree-kit.git worktree-kit

# 2. Create a justfile
echo 'import "worktree-kit/worktree.just"' > justfile

# 3. Add wt.base-port labels to docker-compose.yml (see Setup section below)

# 4. Use it
just wt-dev feature/auth    # creates worktree + starts Docker + health-checks
cd .worktrees/feature/auth   # ready to work
```

## How It Works

Each worktree gets a **slot** (1–9). Ports offset by slot number:

| Slot | API  | DB   | Redis |
|------|------|------|-------|
| 0 (main) | 8000 | 5432 | 6379 |
| 1    | 8001 | 5433 | 6380  |
| 2    | 8002 | 5434 | 6381  |

Data directories isolate per slot: `.docker-data/slot-1/db/`, `.docker-data/slot-2/db/`, etc.

## Setup

### Prerequisites

- [`just`](https://github.com/casey/just) >= 1.19
- `git`
- `docker` + `docker compose` (for Docker features)
- `jq` (optional — improves YAML parsing; grep fallback works without it)

### 1. Add worktree-kit to your project

**Option A — git submodule** (recommended, stays updated):

```bash
git submodule add https://github.com/asabedia/worktree-kit.git worktree-kit
```

**Option B — copy** (simpler, no submodule dependency):

```bash
cp -r /path/to/worktree-kit ./worktree-kit
```

### 2. Import in your justfile

Create a `justfile` in your project root (or add to your existing one):

```just
import "worktree-kit/worktree.just"

# your project recipes below
dev:
    npm run dev
```

### 3. Add labels to docker-compose.yml

Add `wt.base-port` labels to each service you want port-isolated. Use `${WT_*}` env vars in the `ports` and `volumes` mappings with sensible defaults for slot 0 (main repo):

```yaml
services:
  api:
    build: .
    labels:
      wt.base-port: "8000"            # tells worktree-kit the base port
    ports:
      - "${WT_API_PORT:-8000}:8000"    # host port is dynamic, container port stays fixed

  db:
    image: postgres:16
    labels:
      wt.base-port: "5432"
      wt.data-dir: "/var/lib/postgresql/data"   # opt-in to data isolation
    ports:
      - "${WT_DB_PORT:-5432}:5432"
    volumes:
      - ${WT_DB_DATA:-./.docker-data/db}:/var/lib/postgresql/data
```

**Key points:**
- `wt.base-port` — the port number used in slot 0; worktree-kit adds the slot number to compute the host port
- `wt.data-dir` — opt-in; tells worktree-kit this service needs an isolated data directory per slot
- The `:-default` syntax means the main repo (slot 0) works without any env vars set
- Container-internal ports stay the same — only host-mapped ports change
- Services talk to each other via Docker's internal network (service names), unaffected by port offsets

### 4. Add to .gitignore

```
.worktrees/
.docker-data/
.env*.local
```

## Usage

```bash
# Create a worktree for a new branch (off main by default)
just wt-new feature/auth

# Or branch off a specific base
just wt-new feature/auth develop

# cd into it
cd .worktrees/feature/auth

# Start services — ports are automatically offset
just wt-up -d

# Check your slot and port assignments
just wt-status
# → Slot: 1
# → WT_API_PORT=8001
# → WT_DB_PORT=5433

# View logs
just wt-logs

# Stop services
just wt-down

# When done, remove the worktree (from main repo)
cd ../..
just wt-rm feature/auth
```

You can run multiple worktrees simultaneously — each gets its own ports and data.

## Agent-Ready Worktrees

`wt-dev` creates a worktree where an agent can immediately run tests — no manual Docker setup needed:

```bash
just wt-dev feature/auth
```

This runs the full bootstrap:
1. **`wt-doctor`** — verify git, just, docker, and project-specific tools
2. **`wt-new`** — create worktree, allocate slot, install deps, run hooks
3. **`wt-docker-ready`** — pull images, start services, TCP health-check all ports

When it finishes, every service is responding and the worktree is ready for `just test`.

### Health Checks

Verify services are responding in the current worktree:

```bash
just wt-health
```

This TCP-probes every `WT_*_PORT` without restarting containers.

### Requirement Checks

`wt-doctor` runs automatically as part of `wt-dev`. You can also run the script directly:

```bash
scripts/wt-doctor.sh .
```

To declare project-specific tool requirements, create `.wt-required-tools` in your project root:

```
# one tool per line, # comments
node
psql
redis-cli
```

## Compose Setup Guide

For `wt-dev` to work well (especially with AI agents), your compose setup needs **volume mounts** and **hot-reload** so code changes reflect instantly without rebuilds.

### Volume Mounts

Mount your source code into the container so edits on the host are visible immediately:

```yaml
# Before — changes require rebuild
services:
  api:
    build: .

# After — changes reflect instantly
services:
  api:
    build: .
    volumes:
      - ./src:/app/src    # source code mounted in
```

For Node.js services, preserve the container's `node_modules`:

```yaml
  frontend:
    volumes:
      - ./frontend:/app
      - /app/node_modules   # anonymous volume keeps container deps
```

### Hot-Reload

Use dev servers that watch for file changes:

| Stack | Command | Watches |
|-------|---------|---------|
| Python/FastAPI | `uvicorn main:app --reload` | `*.py` files |
| Node/Vite | `vite --host 0.0.0.0` | `src/`, `index.html` |
| Node/Next.js | `next dev` | `pages/`, `app/` |
| Go/Air | `air` | `*.go` files |

### Internal Networking

Services talk to each other by **service name** over Docker's internal network. Port offsets only affect host-mapped ports:

```yaml
  backend:
    environment:
      - DATABASE_URL=postgresql://postgres:postgres@db:5432/app
      #                                           ^^ service name, not localhost
```

See [`examples/monolith/`](examples/monolith/) for a complete working setup.

## Env Var Naming

Service names map to env vars: **uppercase, hyphens/dots to underscores**.

| Service     | Port Var            | Data Var            |
|-------------|---------------------|---------------------|
| `api`       | `WT_API_PORT`       | —                   |
| `db`        | `WT_DB_PORT`        | `WT_DB_DATA`        |
| `foo-bar`   | `WT_FOO_BAR_PORT`   | `WT_FOO_BAR_DATA`   |
| `baz.qux`   | `WT_BAZ_QUX_PORT`   | `WT_BAZ_QUX_DATA`   |

## Recipes

| Recipe               | Description                                        |
|----------------------|----------------------------------------------------|
| `wt-new branch [base]` | Create worktree + allocate slot + install deps  |
| `wt-dev branch [base]` | `wt-new` + Docker pull/start/health-check (agent-ready) |
| `wt-rm branch`       | Remove worktree + release slot + offer data cleanup |
| `wt-up *args`        | `docker compose up --build` with slot env           |
| `wt-down *args`      | `docker compose down` with slot env                 |
| `wt-logs *args`      | `docker compose logs -f` with slot env              |
| `wt-status`          | Show slot, ports, active slots                      |
| `wt-health`          | TCP health-check all `WT_*_PORT` services           |
| `wt-list`            | `git worktree list` + slot assignments              |
| `wt-cd branch`       | Print worktree path (use: `cd $(just wt-cd branch)`) |
| `wt-clean`           | Remove worktrees whose branches are merged into main |
| `wt-prune`           | `git worktree prune -v`                             |

## Configuration

Override in your justfile **before** the import:

```just
wt-dir            := ".worktrees"     # where worktrees are created
wt-max-slots      := "9"              # max concurrent worktrees (1-9)
wt-data-root      := ".docker-data"   # docker data root directory
wt-health-timeout := "60"             # seconds to wait for service health

import "worktree-kit/worktree.just"
```

Or via environment variables:
- `WT_MAX_SLOTS` — max slots (default 9)
- `WT_DATA_ROOT` — data root (default `.docker-data`)

## Compose Label Reference

| Label           | Required | Description                                |
|-----------------|----------|--------------------------------------------|
| `wt.base-port`  | Yes*     | Base port number for the service           |
| `wt.data-dir`   | No       | Container path that needs data isolation   |

\* Required for port isolation. Services without labels are ignored by worktree-kit but work normally in compose.

## Auto-Detected Dependencies

When `wt-new` creates a worktree, it automatically installs dependencies:

| Detected File       | Tool Used |
|----------------------|-----------|
| `bun.lockb`/`bun.lock` | `bun install` |
| `pnpm-lock.yaml`    | `pnpm install` |
| `yarn.lock`         | `yarn install` |
| `package.json`      | `npm install` |
| `pyproject.toml` (poetry) | `poetry install` |
| `pyproject.toml` (uv) | `uv sync` |
| `requirements.txt`  | `pip install -r` |
| `go.mod`            | `go mod download` |
| `Cargo.toml`        | `cargo fetch` |

## Project Hook

For custom post-setup logic (e.g., running migrations, seeding data), create an executable script at `scripts/wt-post-setup.sh` in your project. It runs after slot allocation and dependency installation.

```bash
#!/bin/bash
# scripts/wt-post-setup.sh
echo "Running migrations..."
just db-migrate
```

## Claude Code Plugin

The `worktree-kit-onboard` plugin provides an interactive `/wt-onboard` command that automates the entire setup process.

### Install

```bash
/plugin marketplace add asabedia/worktree-kit
/plugin install worktree-kit-onboard@worktree-kit
```

### What it does

Run `/wt-onboard` from any project repo. The wizard:

1. Scans your codebase — detects stack (Python, Node, Go, Rust, Ruby, Java), frameworks, services, existing Dockerfiles
2. Walks through each service — confirms name, port, Dockerfile, volume mounts, hot-reload command
3. Generates all files — `docker-compose.yml` with `wt.*` labels, `justfile`, Dockerfiles, `.wt-required-tools`, post-setup hooks
4. Validates — runs `wt-doctor.sh` to verify everything works

Supports single-service repos and full-stack monoliths (backend + frontend).

If something blocks integration (no git repo, no entrypoint), it tells you exactly what to fix.

## Examples

See the [`examples/`](examples/) directory:

- **[`basic/`](examples/basic/)** — single Redis service with port isolation
- **[`full-stack/`](examples/full-stack/)** — API + MongoDB + Web frontend with port and data isolation
- **[`monolith/`](examples/monolith/)** — backend + frontend + Postgres with volume mounts and hot-reload (recommended starting point)

## License

MIT
