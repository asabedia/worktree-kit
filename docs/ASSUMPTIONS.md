# Assumptions

Core invariants of worktree-kit.

## Worktree Layout

- Worktrees live under a single `wt-dir` (default `.worktrees/`) in the project root
- Each worktree = one branch = one subdirectory
- The main repo is always slot 0 (no marker file, default ports)

## Slot System

- Slots are integers 1–N (configurable max, default 9)
- Marker files: `.worktrees/.slot-N` containing the branch name
- Slot 0 is implicit — the main repo, never allocated
- One slot per worktree, one worktree per slot

## Port Isolation

- Port offset = slot number (`base_port + slot`)
- Slot 0 uses base values unchanged
- Labels in `docker-compose.yml` are the single source of truth for base ports
- Env vars follow `WT_{SERVICE}_PORT` naming convention

## Data Isolation

- Slot 0: `{data_root}/{service}/`
- Slot N: `{data_root}/slot-N/{service}/`
- Data root defaults to `.docker-data/`

## Environment

- `WT_SLOT` stored in worktree's `.env.local`
- `.env.local` is gitignored (per-worktree state)
- `set dotenv-load` in justfile reads `.env.local` automatically

## Docker Compose

- All dev services defined in a single `docker-compose.yml`
- Internal docker networking unaffected (services talk to each other by service name)
- Only host-mapped ports need isolation
- Labels use `wt.*` namespace
