#!/bin/bash
#
# Logging and run-summary helpers. All output goes to stderr or
# $GITHUB_STEP_SUMMARY - never stdout - so callers that capture a function's
# stdout (a version string, JSON, ...) are never polluted by log lines.

# Log version check results
# Args: $1 - current version, $2 - latest version, $3 - update decision (needed/skipped)
log_version_check() {
    local current_version="$1"
    local latest_version="$2"
    local decision="$3"

    echo "=== Version Check Results ===" >&2
    echo "Current version: ${current_version:-not deployed}" >&2
    echo "Latest available version: ${latest_version:-unknown}" >&2
    echo "Decision: $decision" >&2
    echo "============================" >&2
}

# Log successful deployment
# Args: $1 - deployed version
log_deployment_success() {
    local version="$1"

    echo "=== Deployment Successful ===" >&2
    echo "Successfully deployed n8n version: $version" >&2
    echo "============================" >&2
}

# Log deployment failure
# Args: $1 - version attempted, $2 - error details
log_deployment_failure() {
    local version="$1"
    local error_details="$2"

    echo "=== Deployment Failed ===" >&2
    echo "Failed to deploy n8n version: $version" >&2
    echo "Error details:" >&2
    echo "$error_details" >&2
    echo "========================" >&2
}

# Create workflow summary
# Args: $1 - action (checked/deployed/skipped), $2 - current version, $3 - latest version
create_workflow_summary() {
    local action="$1"
    local current_version="$2"
    local latest_version="$3"

    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "                   📊 WORKFLOW SUMMARY                              " >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2

    # Determine icon based on action
    local action_icon="ℹ️"
    if [[ "$action" == *"deployed"* ]] && [[ "$action" != *"failed"* ]]; then
        action_icon="✅"
    elif [[ "$action" == *"failed"* ]]; then
        action_icon="❌"
    elif [[ "$action" == *"skipped"* ]]; then
        action_icon="⏭️"
    fi

    echo "  $action_icon  Action:          $action" >&2
    echo "  📦  Current Version:  ${current_version:-not deployed}" >&2
    echo "  🆕  Latest Version:   ${latest_version:-unknown}" >&2
    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2

    # Also write to GitHub Actions summary if available
    if [ -n "$GITHUB_STEP_SUMMARY" ]; then
        {
            echo "## 📊 n8n Auto-Deploy Summary"
            echo ""
            echo "| Item | Value |"
            echo "|------|-------|"
            echo "| $action_icon Action | $action |"
            echo "| 📦 Current Version | ${current_version:-not deployed} |"
            echo "| 🆕 Latest Version | ${latest_version:-unknown} |"
            echo ""
            if [[ "$action" == *"deployed"* ]] && [[ "$action" != *"failed"* ]]; then
                echo "✅ **Deployment successful!** Your n8n instance is now running version $latest_version"
            elif [[ "$action" == *"failed"* ]]; then
                echo "❌ **Deployment failed.** Please check the logs above for details."
            elif [[ "$action" == *"skipped"* ]]; then
                echo "✅ **Already up to date!** No deployment needed."
            fi
        } >> "$GITHUB_STEP_SUMMARY"
    fi
}
