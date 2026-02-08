# End-to-End Test Plan

Three test axes: single-project isolation, cross-project isolation, complex dependency isolation.

## Test Projects

- **project-alpha**: API (Flask, port 8000) + Postgres (5432)
- **project-beta**: API (Express, port 8000) + Redis (6379) + Mongo (27017)

Both import `worktree.just`, use `wt.*` labels.

---

## 1. Single-Project Isolation (project-alpha)

- **1a** Create worktree `feature/a` → gets slot 1, ports 8001/5433
- **1b** Create worktree `feature/b` → gets slot 2, ports 8002/5434
- **1c** `wt-up -d` in both → both compose stacks start, no port conflicts
- **1d** Hit API on :8001 and :8002 → different responses (or at least both respond)
- **1e** Write data to postgres on :5433, confirm :5434 has no such data
- **1f** `wt-status` in each → shows correct slot/port mapping
- **1g** `wt-rm feature/a` → slot 1 released, data cleanup prompt works
- **1h** Create `feature/c` → reuses slot 1
- **1i** Main repo (slot 0) → `wt-up` uses default ports 8000/5432, no conflict with slot 2

## 2. Cross-Project Isolation (alpha + beta)

- **2a** Both projects have a service on base-port 8000 — verify alpha slot 1 (8001) and beta slot 1 (8001) conflict if run simultaneously
- **2b** Assign beta slot 2 instead → alpha :8001, beta :8002, no conflict
- **2c** Slot files are per-project (each has its own `.worktrees/`) — allocating in alpha doesn't consume beta's slots
- **2d** Data dirs are per-project — alpha's `.docker-data/slot-1/` is under alpha's root, beta's under beta's

> Note: 2a is an expected limitation — cross-project port collision is the user's responsibility. Document this.

## 3. Complex Dependency Isolation (project-beta: Redis message broker)

- **3a** Redis on slot 0 (:6379), slot 1 (:6380), slot 2 (:6381) — all reachable
- **3b** Publish message to Redis on :6380, confirm :6381 doesn't receive it
- **3c** API connects to Redis via internal docker network (service name) — verify internal connectivity unaffected by port offset
- **3d** Mongo data isolation: write doc on slot 1, absent on slot 2
- **3e** `wt-env.sh` output includes all three services: `WT_API_PORT`, `WT_REDIS_PORT`, `WT_MONGO_PORT`
- **3f** Slot teardown cleans up all three data dirs (not just one service)

## Edge Cases

- **E1** Exhaust all 9 slots → `wt-new` fails with clear error
- **E2** Remove worktree manually (not via `wt-rm`) → slot marker orphaned, `wt-list` still shows it
- **E3** No `docker-compose.yml` → `wt-env.sh` exits 0, no env vars, `wt-new` still works (slot + deps only)
- **E4** `jq` not installed → grep fallback produces same env output
- **E5** Service named `foo-bar` → env var is `WT_FOO_BAR_PORT`
