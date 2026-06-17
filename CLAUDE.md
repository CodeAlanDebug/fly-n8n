# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

This repo contains **no application code**. It is the deployment automation for a self-hosted n8n
instance running on Fly.io. It checks Docker Hub daily for the latest *stable* n8n release and, if
newer than what's deployed, runs `flyctl deploy --image n8nio/n8n:<version>` against the Fly app.
n8n itself is the upstream `n8nio/n8n` Docker image — it is never built here.

## Architecture

Two files hold all the behavior; everything else is config or docs.

- **`.github/workflows/deploy-n8n.yml`** — orchestration only. A single `check-and-deploy` job whose
  steps `source scripts/version-detection.sh` and call its functions. State passes between steps via
  `$GITHUB_OUTPUT` (`latest_version`, `latest_overall`, `held_major`, `current_version`, `app_name`,
  `needs_update`, `deployment_status`), not env vars or files. The deploy / health-check / summary
  steps are gated on `steps.compare.outputs.needs_update == 'true'`. Triggers: daily cron `0 2 * * *`,
  push to `main`, and manual `workflow_dispatch`. A `concurrency: deploy-n8n` group with
  `cancel-in-progress: false` serializes runs so deploys never overlap.

  **`N8N_MAJOR` (job-level env, currently `'2'`) is the deploy policy knob.** The pipeline only
  auto-deploys minor/patch releases *within this major* (`filter_major` selects the target); a newer
  major is detected (`held_major`) and reported in the summary but never auto-deployed — manual
  approval = bump `N8N_MAJOR` and let it deploy. **Never lower `N8N_MAJOR` below the running major** —
  the deployed instance runs n8n 2.x and its persisted DB cannot be read by an older major
  (downgrade = data loss). This knob exists because n8n shipped 2.x; pinning prevents an unattended
  cron from jumping majors with breaking DB migrations.

- **`scripts/version-detection.sh`** — all logic, as sourced bash functions (no `main`, nothing runs
  on source). The deploy decision flows through these:
  1. `query_dockerhub_tags` → hits `hub.docker.com/v2/repositories/n8nio/n8n/tags`, validates JSON.
  2. `extract_tag_names` → `filter_stable_versions` → `find_latest_version` — the stable filter drops
     anything with a `-`, `beta`, `alpha`, or `rc`, and `find_latest_version` picks the max via
     `version_greater_than` (manual numeric major/minor/patch compare, **not** `sort -V`).
  3. `query_flyio_version` → parses the deployed image tag out of `flyctl status --json`. It tries
     several JSON paths (`.Image`, `.Machines[0].config.image`, `.ImageRef`, …) because Fly's schema
     varies, then `parse_version_from_image` turns the ref into a tag (handles `repo:tag`,
     `host:port/repo`, and `@sha256` digests). **Return-code contract matters:** `2` = auth failure
     (workflow must hard-fail), `0` with empty output = not-yet-deployed (triggers initial deploy),
     `1` = other error. **The `latest`-tag trap:** the instance was originally deployed untagged
     (`n8nio/n8n` → tag `latest`), so Fly reported the literal string `latest` as the "version". A
     non-semver current version fed the old comparison `[: latest: integer expression expected` and
     silently wedged the pipeline at "up to date" — it never deployed. Deploying with an *explicit*
     tag (`n8nio/n8n:2.27.1`) makes Fly report that tag next run, self-correcting out of the trap.
  4. `needs_update` → empty *or non-semver* current version (e.g. `latest`, a digest) means deploy
     (re-pin to an explicit tag); else semver compare. `is_semver` guards `version_greater_than` so
     bad input returns "not greater" instead of erroring.
  5. `deploy_to_flyio` → `flyctl deploy --app <app> --image n8nio/n8n:<version>`. `--image` is what
     preserves volumes/env/config — only the container image changes.
  6. `verify_deployment_health` → counts machines in `started`/`running` state after a 10s settle.
  7. Release-notes functions (`fetch_release_notes`, `create_version_summary`, …) hit the GitHub
     releases API for `n8n@<version>` and write to `$GITHUB_STEP_SUMMARY`. This step is
     `continue-on-error` / non-critical — never let it block a deploy.

  **Convention:** all human-facing/log output goes to **stderr** (`>&2`); stdout is reserved for the
  function's return value (a version string, JSON, etc.) so callers can capture it cleanly. Preserve
  this when editing — moving a log line to stdout will corrupt a captured value.

- **`fly.toml`** — the Fly app config (app `n8n-run`, region `ams`, port 5678, the `n8n_data` volume
  mounted at `/home/node/.n8n`). The workflow reads the app name out of this file with `grep`/`sed`;
  it does not deploy *from* it (deploys are `--image` only). `[build].image` is overridden per-deploy.

## Secrets / external dependencies

- `FLY_API_TOKEN` — GitHub Actions secret, required. Functions check for it but must never echo it.
  Create with `flyctl tokens create deploy`.
- External services with no fallback: Docker Hub tags API, Fly.io (`flyctl`), GitHub releases API.
- Tooling assumed present: `jq`, `curl`, `flyctl` (the workflow installs flyctl via
  `superfly/flyctl-actions/setup-flyctl`).

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
