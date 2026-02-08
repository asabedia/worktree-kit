# Extensibility

Known pain points and extension paths.

## Multiple Ports Per Service

Some services expose multiple ports (e.g., HTTP + gRPC). Currently only one `wt.base-port` per service.

**Workaround:** Split into separate compose services, or manually set extra port env vars in `scripts/wt-post-setup.sh`.

**Future:** `wt.extra-port.{name}: "9090"` label → `WT_{SERVICE}_{NAME}_PORT`.

## Custom Setup Hooks

Projects can add `scripts/wt-post-setup.sh` (must be executable) for project-specific setup after worktree creation. Runs after slot allocation and dependency installation.

Examples: seed databases, generate config files, register with external services.

## Compose Profiles

Pass `--profile` via `wt-up` args: `just wt-up --profile debug -d`.

## Max Slots Limit

Default 9 (single-digit for readability). Override via `WT_MAX_SLOTS` env var or `wt-max-slots` justfile variable. Going above ~20 may conflict with other services' port ranges.

## Non-Docker Services

Slot allocation still works for non-Docker projects. Services can read `WT_SLOT` from `.env.local` and compute their own port offsets. The `wt-env.sh` script gracefully exits if no compose file exists.

## Inter-Service Connectivity

Internal docker network is unaffected by port isolation — containers always talk to each other using internal ports and service names. Only host-mapped ports are offset.

## Alternative Compose Files

Pass a custom compose file: `just wt-up -f docker-compose.dev.yml`. The `wt-env.sh` script accepts the compose file path as its second argument.

## CI/CD

In CI, set `WT_SLOT` explicitly to avoid conflicts between parallel jobs:

```bash
export WT_SLOT=$CI_JOB_INDEX
eval $(./scripts/wt-env.sh $WT_SLOT)
docker compose up -d
```
