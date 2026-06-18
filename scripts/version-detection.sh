#!/bin/bash
#
# Aggregator for the n8n auto-deploy helpers.
#
# Callers (the GitHub Actions workflow and the bats tests) source THIS file and
# get every function, exactly as before the code was split into lib/ modules.
# The functions themselves now live in scripts/lib/*.sh, grouped by concern:
#   logging.sh        - log_* and create_workflow_summary
#   dockerhub.sh      - query_dockerhub_tags, extract_tag_names
#   versions.sh       - semver logic, the deploy decision, fly.toml read/write
#   flyio.sh          - flyctl: query/deploy/health
#   release_notes.sh  - GitHub release notes for the run summary
#
# SECURITY NOTE: the flyio.sh functions handle FLY_API_TOKEN. They check for it
# but never echo it; GitHub Actions also masks secrets in logs.
#
# Nothing here runs on source - these are function definitions only. Order does
# not matter (cross-module calls resolve at call time, once all are loaded).

_vd_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"

# shellcheck source=lib/logging.sh
source "${_vd_lib_dir}/logging.sh"
# shellcheck source=lib/dockerhub.sh
source "${_vd_lib_dir}/dockerhub.sh"
# shellcheck source=lib/versions.sh
source "${_vd_lib_dir}/versions.sh"
# shellcheck source=lib/flyio.sh
source "${_vd_lib_dir}/flyio.sh"
# shellcheck source=lib/release_notes.sh
source "${_vd_lib_dir}/release_notes.sh"

unset _vd_lib_dir
