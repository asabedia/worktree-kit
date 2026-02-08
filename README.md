# worktree-kit

Reusable git worktree + Docker isolation toolkit. Run parallel feature branches with isolated ports and data — zero config conflicts.

## Quick Start

1. Copy or submodule `worktree-kit` into your project (or install globally)

2. Add `wt.*` labels to your `docker-compose.yml`:

```yaml
services:
  api:
    labels:
      wt.base-port: "8000"
    ports:
      - "${WT_API_PORT:-8000}:8000"
  db:
    labels:
      wt.base-port: "5432"
      wt.data-dir: "/var/lib/postgresql/data"
    ports:
      - "${WT_DB_PORT:-5432}:5432"
    volumes:
      - ${WT_DB_DATA:-./.docker-data/db}:/var/lib/postgresql/data
```

3. Import in your `justfile`:

```just
import "path/to/worktree-kit/worktree.just"
```

4. Add to `.gitignore`:

```
.worktrees/
.docker-data/
.env*.local
```

5. Use it:

```bash
just wt-new feature/auth        # create worktree, allocate slot, install deps
just wt-up -d                   # start services on isolated ports
just wt-status                  # show port mapping
just wt-rm feature/auth         # clean up
```

## How It Works

Each worktree gets a **slot** (1–9). Ports offset by slot number:

| Slot | API   | DB    | Web  |
|------|-------|-------|------|
| 0    | 8000  | 5432  | 3000 |
| 1    | 8001  | 5433  | 3001 |
| 2    | 8002  | 5434  | 3002 |

Data directories isolate per slot: `.docker-data/slot-N/service/`.

## Env Var Naming

Service names map to env vars: **uppercase, hyphens → underscores**.

| Service    | Port Var           | Data Var           |
|------------|--------------------|--------------------|
| `api`      | `WT_API_PORT`      | —                  |
| `mongo`    | `WT_MONGO_PORT`    | `WT_MONGO_DATA`    |
| `foo-bar`  | `WT_FOO_BAR_PORT`  | `WT_FOO_BAR_DATA`  |

## Recipes

| Recipe | Description |
|--------|-------------|
| `wt-new branch [base]` | Create worktree + allocate slot + install deps |
| `wt-rm branch` | Remove worktree + release slot + offer data cleanup |
| `wt-up *args` | `docker compose up --build` with slot env |
| `wt-down *args` | `docker compose down` with slot env |
| `wt-logs *args` | `docker compose logs -f` with slot env |
| `wt-status` | Show slot, ports, active slots |
| `wt-list` | `git worktree list` + slot assignments |
| `wt-cd branch` | Print worktree path |
| `wt-clean` | Remove merged worktrees |
| `wt-prune` | `git worktree prune -v` |

## Configuration

Override in your justfile before the import:

```just
wt-dir       := ".worktrees"     # worktree directory
wt-max-slots := "9"              # max concurrent worktrees
wt-data-root := ".docker-data"   # docker data root
```

Or via environment:
- `WT_MAX_SLOTS` — max slots (default 9)
- `WT_DATA_ROOT` — data root (default `.docker-data`)

## Compose Label Contract

| Label | Required | Description |
|-------|----------|-------------|
| `wt.base-port` | Yes (for port isolation) | Base port number for the service |
| `wt.data-dir` | No | Container path that needs data isolation |

## Requirements

- `just` >= 1.19
- `git`
- `docker` + `docker compose` (for Docker features)
- `jq` (optional, improves YAML parsing accuracy; grep fallback works without it)

## Project Hook

Create `scripts/wt-post-setup.sh` (executable) in your project for custom post-setup logic. It runs after slot allocation and dependency installation.

## License

MIT
