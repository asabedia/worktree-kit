# worktree-kit

Run parallel feature branches with isolated Docker ports and data — zero config conflicts.

**The problem:** You're working on `feature/auth` with `docker compose up`, then need to context-switch to `feature/payments`. You either tear down your stack or get port conflicts. With worktree-kit, each branch gets its own worktree with automatically offset ports and isolated data directories.

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
git submodule add https://github.com/user/worktree-kit.git worktree-kit
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
| `wt-rm branch`       | Remove worktree + release slot + offer data cleanup |
| `wt-up *args`        | `docker compose up --build` with slot env           |
| `wt-down *args`      | `docker compose down` with slot env                 |
| `wt-logs *args`      | `docker compose logs -f` with slot env              |
| `wt-status`          | Show slot, ports, active slots                      |
| `wt-list`            | `git worktree list` + slot assignments              |
| `wt-cd branch`       | Print worktree path (use: `cd $(just wt-cd branch)`) |
| `wt-clean`           | Remove worktrees whose branches are merged into main |
| `wt-prune`           | `git worktree prune -v`                             |

## Configuration

Override in your justfile **before** the import:

```just
wt-dir       := ".worktrees"     # where worktrees are created
wt-max-slots := "9"              # max concurrent worktrees (1-9)
wt-data-root := ".docker-data"   # docker data root directory

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

## Examples

See the [`examples/`](examples/) directory:

- **[`basic/`](examples/basic/)** — single Redis service with port isolation
- **[`full-stack/`](examples/full-stack/)** — API + MongoDB + Web frontend with port and data isolation

## License

MIT
