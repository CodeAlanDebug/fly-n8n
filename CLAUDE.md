# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

This repo contains **no application code**. It is the deployment automation for a self-hosted n8n
instance running on Fly.io. Daily, it resolves the version n8n promotes to its `:latest` Docker tag
(by digest → explicit `X.Y.Z`), and if that's newer than what's deployed *within the pinned major*,
it `flyctl deploy`s that **explicit** version tag and records it in `fly.toml`. n8n itself is the
upstream `n8nio/n8n` Docker image — never built here.

**Two deployers, reconciled (important history):** a **Fly deploy-on-push trigger** (a Fly GitHub App,
confirmed via `gh api repos/.../deployments` showing `fly-io[bot]`; configured outside this repo and
not reliably disablable) coexists with this workflow. It used to deploy `fly.toml`'s then-untagged
`n8nio/n8n` (= `:latest`) and race/overwrite this workflow's deploy — and that floating `:latest` is
what wedged version detection (see the trap below). The fix is **pinning `fly.toml` to an explicit
tag**: now whenever the Fly trigger fires it deploys that same pinned version, never `:latest`, so the
two deployers can't conflict. This workflow is the *reliable* deployer (flyctl); the Fly trigger is a
harmless echo. **Tracking choice:** the updater follows n8n's promoted `:latest` (not the highest
published tag), because n8n may publish a higher tag (e.g. `2.27.1`) before promoting it to `:latest`
(which was `2.26.6`).

## Architecture

Two files hold all the behavior; everything else is config or docs.

- **`.github/workflows/deploy-n8n.yml`** (job `check-and-deploy`) — orchestration only. Steps
  `source scripts/version-detection.sh` and call its functions. State passes between steps via
  `$GITHUB_OUTPUT` (`target_version`, `resolved`, `held_major`, `current_version`, `needs_update`,
  `deployment_status`). Deploy/health/pin steps are gated on `needs_update == 'true'`. Triggers: daily
  cron `0 2 * * *`, push to `main`, manual `workflow_dispatch`. Flow: detect target → read current
  (from `fly.toml`) → compare → `deploy_to_flyio` (flyctl) → poll health (up to 120s) → commit the new
  pin into `fly.toml` (`permissions: contents: write`, pushed as `github-actions[bot]`). The fly.toml
  commit is recorded *after* a confirmed-healthy deploy, so `fly.toml` never claims a version that
  isn't actually running.

  **`N8N_MAJOR` (job-level env, currently `'2'`) is the policy knob.** If n8n's `:latest` resolves to a
  major greater than this, it's reported (`held_major`) but not deployed — to move majors, bump
  `N8N_MAJOR`. **Never lower it below the running major** (downgrade = data loss; the 2.x DB can't be
  read by 1.x).

- **`scripts/version-detection.sh`** — all logic, as sourced bash functions (no `main`, nothing runs
  on source). The deploy decision flows through these:
  1. `query_dockerhub_tags` → hits `hub.docker.com/v2/repositories/n8nio/n8n/tags`, validates JSON.
  2. `resolve_latest_version "$json"` → finds the `latest` tag's digest, then the highest stable
     `X.Y.Z` tag sharing that digest. This is **what n8n promotes as `:latest`, as an explicit tag** —
     we deploy that, never the floating `:latest`. (`filter_stable_versions`/`find_latest_version`/
     `version_greater_than` are the helpers; comparison is manual numeric, **not** `sort -V`.)
  3. `read_pinned_version fly.toml` → greps the `[build] image` line, runs `parse_version_from_image`
     (handles `repo:tag`, `host:port/repo`, `@sha256` digests). **This is the source of "current"** —
     read from `fly.toml`'s explicit tag, never `flyctl status`, so the `:latest` string can't enter.
     Sound because the deploy step keeps `fly.toml` in sync with what it actually deployed.
  4. `needs_update` → empty/non-semver current or held target → handled; else semver compare.
     `is_semver` guards `version_greater_than` so bad input returns "not greater" not an error.
  5. `deploy_to_flyio <version> <app>` → `flyctl deploy --app <app> --image n8nio/n8n:<version>`
     (`--image` preserves volumes/env). `verify_deployment_health` polls machine state post-deploy.
  6. `bump_flytoml_image fly.toml <version>` → portable `sed -i.bak` rewrite of the image line,
     committed after a healthy deploy.
  7. Release-notes functions (`fetch_release_notes`, `create_version_summary`, …) → GitHub releases API
     for the run summary; `continue-on-error`, never blocks the deploy.

  **The `latest`-tag trap (root cause history):** the instance was deployed untagged (`n8nio/n8n` →
  tag `latest`), so `flyctl status` reported the literal string `latest` as the version. That non-semver
  value hit `[: latest: integer expression expected` and silently wedged the old pipeline at "up to
  date". Fixed structurally: deploy explicit tags, pin `fly.toml`, read current from `fly.toml`.

  **Convention:** human-facing/log output goes to **stderr** (`>&2`); stdout is the function's return
  value (a version string, etc.) so callers can capture it cleanly. Moving a log line to stdout corrupts
  a captured value — that bit us once (a log containing the word "deployed" broke a test asserting
  output had no "deploy").

- **`fly.toml`** — the Fly app config (app `n8n-run`, region `ams`, port 5678, `n8n_data` volume at
  `/home/node/.n8n`) **and the recorded deployed n8n version**: `[build].image = 'n8nio/n8n:<version>'`,
  currently `2.26.6` (= what `:latest` resolves to, = what's running). **Never set it to an untagged
  image** — that reintroduces the `:latest` trap and makes the Fly trigger publish `:latest`. The deploy
  workflow keeps this tag in sync with reality.

## Secrets / external dependencies

- `FLY_API_TOKEN` — GitHub Actions secret, required by the deploy + health steps (`flyctl`). Create
  with `flyctl tokens create deploy`. Never echo it.
- The pin step commits `fly.toml` with the built-in `GITHUB_TOKEN` (`permissions: contents: write`).
- External services with no fallback: Docker Hub tags API, Fly.io (`flyctl`), GitHub releases API.
- Tooling assumed present in CI: `jq`, `curl`, `flyctl` (installed via `superfly/flyctl-actions`).
- `query_flyio_version` is now unused (current comes from `fly.toml`); still tested, harmless — a
  cleanup candidate for the planned decomposition.

## Tests

`tests/version-detection.bats` (~120 cases) is a [bats](https://github.com/bats-core/bats-core) suite.
It tests the pure functions by `source`-ing the script and **stubbing `curl`/`flyctl` as shell
functions** — no real network or Fly calls. bats is not installed by default.

```bash
brew install bats-core              # one-time
bats tests/version-detection.bats   # run all
bats tests/version-detection.bats -f "API error handling"   # run by name filter
```

When you add or change a function, keep its stdout-is-the-value / stderr-is-logs contract and its
documented return codes intact, or the stubs in the bats suite will break.

## Lint

Pre-commit runs `check-yaml`, `end-of-file-fixer`, `trailing-whitespace`, and `yamllint`
(120-col limit). Install/run:

```bash
pre-commit install          # one-time
pre-commit run --all-files
```

## Specs

`.kiro/specs/n8n-auto-deploy/` holds the original `requirements.md` / `design.md` / `tasks.md`
(EARS-style acceptance criteria). Consult these when changing deploy behavior — e.g. requirement 1.3
(ignore pre-releases) and 1.4 (log + retry next run on API failure) are the source of the stable
filter and the non-fatal error handling.
