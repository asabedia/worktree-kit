---
description: Onboard this project to worktree-wizard — interactive setup wizard
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion, Task
---

Integrate worktree-wizard into the current project. This is a step-by-step interactive wizard.

Use the `worktree-wizard-integration` skill for all conventions (wt.base-port labels, WT_* env var patterns, volume mounts, hot-reload configs, Dockerfile patterns per framework).

## Step 1: Analyze Project

Launch the `project-analyzer` agent to scan the codebase. Wait for its structured report before continuing.

If blockers are found:
- Clearly explain each blocker
- Tell the user exactly what steps to take (e.g., "Create a main.py entry point", "Initialize a git repo with `git init`")
- Stop here — do not proceed until blockers are resolved

If the project already has full worktree-wizard integration (justfile import + compose with wt.* labels), inform the user and ask if they want to re-run setup or update specific parts.

## Step 2: Install Method

Ask the user how to add worktree-wizard to their project using AskUserQuestion:
- **Git submodule** — `git submodule add <repo-url> worktree-wizard`
- **Copy files** — copy worktree-wizard directory into the project

For git submodule: ask the user for the repository URL (or suggest the default).
For copy: ask the user for the source path to worktree-wizard.

Execute the chosen installation method. Verify worktree-wizard files are present (specifically `worktree.just` and `scripts/` directory).

## Step 3: Configure Services (step-by-step)

For each service detected by the analyzer, walk through configuration one at a time:

**3a. Confirm service details:**
Present what was detected and ask the user to confirm/adjust:
- Service name (used in compose and env var naming)
- Base port (suggest framework default — e.g., 8000 for FastAPI, 3000 for Vite)
- Whether it needs data isolation (only for databases/stateful services)

**3b. Dockerfile:**
- If a Dockerfile exists: read it, check if it has a dev-friendly CMD (hot-reload). If not, suggest changes.
- If no Dockerfile exists: generate one using the framework pattern from the skill's `references/stack-patterns.md`. Show it to the user and confirm before writing.

**3c. Volume mounts and hot-reload:**
- Propose volume mount based on project shape (root mount vs subdirectory mount)
- For Node.js services, always include the anonymous `/app/node_modules` volume
- Confirm the dev command supports hot-reload (check existing package.json scripts, Procfile, etc.)
- If dev script needs `--host 0.0.0.0` flag (Vite, Next.js), note this and offer to update package.json

**3d. Infrastructure services:**
For detected databases/caches, ask the user to confirm:
- Image version (suggest latest stable)
- Whether data isolation is needed (recommend yes for databases)
- Default credentials for dev (suggest sensible defaults)

## Step 4: External Requirements

Ask the user about:
- **Additional CLI tools** needed for development (beyond git, just, docker) — these go into `.wt-required-tools`
- **Post-setup hook** — any commands to run after worktree creation? (migrations, seed data, env setup). If yes, generate `scripts/wt-post-setup.sh`

If the user mentions needing something done that cannot be automated (e.g., "get API keys from team lead", "sign up for a service"), note these as manual steps and list them at the end.

## Step 5: Generate Files

Generate all files. For each file, show the user what will be written and write it:

1. **docker-compose.yml** — all services with wt.* labels, WT_* env vars with defaults, volume mounts, hot-reload commands, proper depends_on ordering
2. **justfile** — import worktree.just, with any config var overrides needed
3. **.gitignore additions** — append `.worktrees/`, `.docker-data/`, `.env*.local` if not already present
4. **.wt-required-tools** — if any tools were specified
5. **scripts/wt-post-setup.sh** — if post-setup hook was requested
6. **Dockerfiles** — for any services that need them (in their respective directories)

When writing docker-compose.yml:
- Use the exact env var naming convention: `WT_{SERVICE_UPPER}_PORT`
- Always include `:-default` fallbacks
- Use service names (not localhost) for inter-service communication
- Set appropriate `depends_on` ordering

When writing the justfile:
- Check if a justfile already exists — if so, add the import line rather than overwriting
- Place `import` at the top of the file

## Step 6: Validate

Run the worktree-wizard doctor script to verify the setup:
```
worktree-wizard/scripts/wt-doctor.sh .
```

If validation fails, explain what's wrong and fix it.

## Step 7: Summary

Print a summary of everything that was set up:
- Files created/modified (with paths)
- Services configured (with ports)
- Any manual steps the user still needs to complete

Then show the user how to use it:
```
# Create an agent-ready worktree
just wt-dev feature/my-feature

# Or create a worktree without Docker auto-start
just wt-new feature/my-feature
```

If there are manual steps remaining, list them clearly with checkboxes.
