# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

This repo contains **no application code**. It is the deployment automation for a self-hosted n8n
instance running on Fly.io. It checks Docker Hub daily for the latest *stable* n8n release and, if
newer than what's pinned, **bumps the image tag in `fly.toml` and pushes**. The deploy itself is done
by **Fly.io's own deploy-on-push trigger** (a Fly GitHub App, configured outside this repo), which
deploys whatever `fly.toml` pins. n8n itself is the upstream `n8nio/n8n` Docker image — never built here.

**Why this split (important history):** there used to be *two* deployers racing — this workflow ran
`flyctl deploy --image …` while the Fly trigger concurrently deployed `fly.toml`'s then-untagged
`n8nio/n8n` (= `:latest`). The Fly trigger won and kept slapping `:latest` on the app, which is the
floating tag that wedged version detection (see the trap below). The Fly trigger could not be easily
disabled, so the design was inverted: **`fly.toml` is the single source of truth**, this workflow only
*edits the pin*, and the Fly trigger is the sole deployer. One deployer, no race, never `:latest`.

## Architecture

Two files hold all the behavior; everything else is config or docs.

- **`.github/workflows/deploy-n8n.yml`** (job `check-and-bump`) — orchestration only. Steps
  `source scripts/version-detection.sh` and call its functions. State passes between steps via
  `$GITHUB_OUTPUT` (`latest_version`, `latest_overall`, `held_major`, `current_version`,
  `needs_update`, `pushed`). The bump/summary steps are gated on
  `steps.compare.outputs.needs_update == 'true'`. Triggers: daily cron `0 2 * * *`, push to `main`,
  manual `workflow_dispatch`. **It does not deploy** — the bump step edits `fly.toml` and `git push`es;
  Fly's trigger deploys. `permissions: contents: write` is required for that push. The push is authored
  by `github-actions[bot]`/`GITHUB_TOKEN`, which by GitHub's rules does **not** re-trigger this workflow
  (no loop) but **does** reach the Fly GitHub App (deploy fires).

  **`N8N_MAJOR` (job-level env, currently `'2'`) is the policy knob.** The workflow only auto-bumps
  minor/patch releases *within this major* (`filter_major` selects the target); a newer major is
  detected (`held_major`) and reported in the summary but never auto-bumped — to move majors, bump
  `N8N_MAJOR`. **Never lower it below the running major** — the instance runs n8n 2.x and its persisted
  DB cannot be read by an older major (downgrade = data loss).

- **`scripts/version-detection.sh`** — all logic, as sourced bash functions (no `main`, nothing runs
  on source). The bump decision flows through these:
  1. `query_dockerhub_tags` → hits `hub.docker.com/v2/repositories/n8nio/n8n/tags`, validates JSON.
  2. `extract_tag_names` → `filter_stable_versions` → `filter_major "$N8N_MAJOR"` → `find_latest_version`
     — stable filter drops anything with `-`/`beta`/`alpha`/`rc`; max picked via `version_greater_than`
     (manual numeric major/minor/patch compare, **not** `sort -V`).
  3. `read_pinned_version fly.toml` → greps the `[build] image` line and runs `parse_version_from_image`
     on it. **This replaced `query_flyio_version` as the source of current version** — the version now
     comes from the explicit tag in `fly.toml`, never from `flyctl status`. `parse_version_from_image`
     handles `repo:tag`, `host:port/repo`, and `@sha256` digests (digest → empty).
  4. `needs_update` → empty *or non-semver* current (e.g. an untagged image) means bump; else semver
     compare. `is_semver` guards `version_greater_than` so bad input returns "not greater" not an error.
  5. `bump_flytoml_image fly.toml <version>` → portable `sed -i.bak` rewrite of the image line,
     preserving indentation. The workflow commits + pushes the result.
  6. Release-notes functions (`fetch_release_notes`, `create_version_summary`, …) hit the GitHub
     releases API for `n8n@<version>` for the run summary; `continue-on-error`, never blocks the bump.

  **The `latest`-tag trap (root cause history):** the instance was deployed untagged
  (`n8nio/n8n` → tag `latest`), so `flyctl status` reported the literal string `latest` as the version.
  That non-semver value hit `[: latest: integer expression expected` and silently wedged the old
  pipeline at "up to date". The fix is structural: the version is read from `fly.toml`'s explicit tag,
  and `fly.toml` is pinned (never untagged), so `latest` never enters comparison again.

  **Dead code:** `query_flyio_version`, `deploy_to_flyio`, `verify_deployment_health` are no longer
  called by the workflow (the Fly trigger deploys now). They're still tested and harmless; remove them
  (and their tests) during the planned decomposition.

  **Convention:** human-facing/log output goes to **stderr** (`>&2`); stdout is the function's return
  value (a version string, etc.) so callers can capture it cleanly. Moving a log line to stdout corrupts
  a captured value — that bit us once (a log containing the word "deployed" broke a test asserting
  output had no "deploy").

- **`fly.toml`** — the Fly app config (app `n8n-run`, region `ams`, port 5678, `n8n_data` volume at
  `/home/node/.n8n`) **and the single source of truth for the deployed n8n version**:
  `[build].image = 'n8nio/n8n:<version>'`, currently pinned. **Never set it back to an untagged image**
  — that reintroduces the `:latest` trap. To change versions, edit this tag (the workflow does this
  automatically); the Fly trigger deploys it on push.

## Secrets / external dependencies

- **No `FLY_API_TOKEN` needed by the workflow anymore** — it doesn't call `flyctl` (the Fly trigger
  deploys). The legacy `flyctl` functions still reference the token, but they're dead code. Fly auth
  lives entirely in the Fly GitHub App / trigger now.
- The bump step pushes with the built-in `GITHUB_TOKEN` (granted by `permissions: contents: write`).
- External services with no fallback: Docker Hub tags API, GitHub releases API.
- Tooling assumed present in CI: `jq`, `curl` (no flyctl install step anymore).

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
