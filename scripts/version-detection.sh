#!/bin/bash

# Version detection functions for n8n Docker Hub monitoring
#
# SECURITY NOTE: This script handles sensitive credentials (FLY_API_TOKEN).
# - Never echo, print, or log the FLY_API_TOKEN value
# - GitHub Actions automatically masks secrets in logs
# - All functions check for token presence but never expose its value

# Logging functions for status reporting

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

# Query Docker Hub API for n8n tags
# Returns: JSON response with tag information or exits with error
query_dockerhub_tags() {
    local api_url="https://hub.docker.com/v2/repositories/n8nio/n8n/tags?page_size=100"
    local response
    local http_code

    # Make API request and capture both response and HTTP status code
    response=$(curl -s -w "\n%{http_code}" "$api_url" 2>&1)
    http_code=$(echo "$response" | tail -n1)
    response=$(echo "$response" | sed '$d')

    # Check if curl command failed
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to connect to Docker Hub API" >&2
        return 1
    fi

    # Check HTTP status code
    if [ "$http_code" != "200" ]; then
        echo "ERROR: Docker Hub API returned HTTP $http_code" >&2
        return 1
    fi

    # Validate JSON response
    if ! echo "$response" | jq empty 2>/dev/null; then
        echo "ERROR: Invalid JSON response from Docker Hub API" >&2
        return 1
    fi

    echo "$response"
    return 0
}

# Extract tag names from Docker Hub API response
# Args: $1 - JSON response from Docker Hub API
# Returns: List of tag names, one per line
extract_tag_names() {
    local json_response="$1"

    if [ -z "$json_response" ]; then
        echo "ERROR: Empty JSON response provided" >&2
        return 1
    fi

    # Extract tag names from results array
    echo "$json_response" | jq -r '.results[]?.name // empty' 2>/dev/null

    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to parse tag names from JSON" >&2
        return 1
    fi

    return 0
}

# Filter stable versions from a list of tags
# Args: Tag names via stdin, one per line
# Returns: Only stable semantic version tags, one per line
filter_stable_versions() {
    while IFS= read -r tag; do
        # Skip empty lines
        [ -z "$tag" ] && continue

        # Filter out non-semantic version tags (latest, next, etc.)
        if [[ ! "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+.*$ ]]; then
            continue
        fi

        # Filter out pre-release versions (containing -, beta, alpha, rc)
        if [[ "$tag" =~ - ]] || [[ "$tag" =~ beta ]] || [[ "$tag" =~ alpha ]] || [[ "$tag" =~ rc ]]; then
            continue
        fi

        # Output stable version
        echo "$tag"
    done
}

# Compare two semantic versions
# Args: $1 - version1, $2 - version2
# Returns: 0 if version1 > version2, 1 if version1 <= version2
version_greater_than() {
    local v1="$1"
    local v2="$2"

    # Split versions into components
    IFS='.' read -ra v1_parts <<< "$v1"
    IFS='.' read -ra v2_parts <<< "$v2"

    # Compare major version
    if [ "${v1_parts[0]}" -gt "${v2_parts[0]}" ]; then
        return 0
    elif [ "${v1_parts[0]}" -lt "${v2_parts[0]}" ]; then
        return 1
    fi

    # Compare minor version
    if [ "${v1_parts[1]}" -gt "${v2_parts[1]}" ]; then
        return 0
    elif [ "${v1_parts[1]}" -lt "${v2_parts[1]}" ]; then
        return 1
    fi

    # Compare patch version
    if [ "${v1_parts[2]}" -gt "${v2_parts[2]}" ]; then
        return 0
    else
        return 1
    fi
}

# Find the latest semantic version from a list
# Args: Version strings via stdin, one per line
# Returns: The highest semantic version
find_latest_version() {
    local latest=""

    while IFS= read -r version; do
        # Skip empty lines
        [ -z "$version" ] && continue

        # If this is the first version, set it as latest
        if [ -z "$latest" ]; then
            latest="$version"
            continue
        fi

        # Compare and update if this version is greater
        if version_greater_than "$version" "$latest"; then
            latest="$version"
        fi
    done

    echo "$latest"
}

# Query current deployed version from Fly.io
# Args: $1 - Fly.io app name
# Returns: Current image tag or empty string if not deployed
# Requires: FLY_API_TOKEN environment variable
query_flyio_version() {
    local app_name="$1"

    if [ -z "$app_name" ]; then
        echo "ERROR: App name is required" >&2
        return 1
    fi

    # Check if FLY_API_TOKEN is set
    if [ -z "$FLY_API_TOKEN" ]; then
        echo "ERROR: FLY_API_TOKEN environment variable is not set" >&2
        return 1
    fi

    # Query Fly.io status
    local status_output
    status_output=$(flyctl status --app "$app_name" --json 2>&1)
    local exit_code=$?

    # Check if command failed
    if [ $exit_code -ne 0 ]; then
        # Check for authentication errors (comprehensive patterns)
        if [[ "$status_output" =~ "authentication" ]] || \
           [[ "$status_output" =~ "unauthorized" ]] || \
           [[ "$status_output" =~ "invalid token" ]] || \
           [[ "$status_output" =~ "token expired" ]] || \
           [[ "$status_output" =~ "invalid credentials" ]]; then
            echo "ERROR: Authentication failed - invalid or missing API token" >&2
            return 2
        fi

        # Check if app doesn't exist or isn't deployed
        if [[ "$status_output" =~ "not found" ]] || [[ "$status_output" =~ "No machines" ]]; then
            echo "WARNING: App not deployed or not found" >&2
            return 0
        fi

        echo "ERROR: Failed to query Fly.io status: $status_output" >&2
        return 1
    fi

    # Parse image from JSON output - try multiple possible locations
    # Fly.io's JSON structure may vary, so we try different paths
    local image

    # Try primary location: .Image
    image=$(echo "$status_output" | jq -r '.Image // empty' 2>/dev/null)

    # Try machine config location: .Machines[0].config.image
    if [ -z "$image" ]; then
        image=$(echo "$status_output" | jq -r '.Machines[0]?.config?.image // empty' 2>/dev/null)
    fi

    # Try alternative machine location: .Machines[0].image_ref
    if [ -z "$image" ]; then
        image=$(echo "$status_output" | jq -r '.Machines[0]?.image_ref // empty' 2>/dev/null)
    fi

    # Try ImageRef field
    if [ -z "$image" ]; then
        image=$(echo "$status_output" | jq -r '.ImageRef // empty' 2>/dev/null)
    fi

    if [ -z "$image" ]; then
        # Debug: Show available fields to help troubleshoot
        echo "WARNING: No image found in Fly.io status" >&2
        echo "DEBUG: Available top-level fields:" >&2
        echo "$status_output" | jq -r 'keys[]' 2>/dev/null | head -10 >&2 || true
        return 0
    fi

    # Extract version tag from image (format: n8nio/n8n:1.2.3)
    local version_tag
    version_tag=$(echo "$image" | sed 's/.*://')

    if [ -z "$version_tag" ]; then
        echo "WARNING: Could not extract version from image: $image" >&2
        return 0
    fi

    echo "$version_tag"
    return 0
}

# Compare current deployed version with latest available version
# Args: $1 - current version, $2 - latest version
# Returns: 0 (true) if update is needed, 1 (false) if no update needed
needs_update() {
    local current_version="$1"
    local latest_version="$2"

    # If current version is empty (not deployed), update is needed
    if [ -z "$current_version" ]; then
        return 0
    fi

    # If latest version is empty, cannot update
    if [ -z "$latest_version" ]; then
        return 1
    fi

    # If versions are equal, no update needed
    if [ "$current_version" = "$latest_version" ]; then
        return 1
    fi

    # Check if latest is greater than current
    if version_greater_than "$latest_version" "$current_version"; then
        return 0
    else
        return 1
    fi
}

# Deploy n8n to Fly.io with specified version
# Args: $1 - version tag to deploy, $2 - app name
# Returns: 0 on success, non-zero on failure
# Requires: FLY_API_TOKEN environment variable
deploy_to_flyio() {
    local version="$1"
    local app_name="$2"

    if [ -z "$version" ]; then
        echo "ERROR: Version is required for deployment" >&2
        return 1
    fi

    if [ -z "$app_name" ]; then
        echo "ERROR: App name is required for deployment" >&2
        return 1
    fi

    # Check if FLY_API_TOKEN is set
    if [ -z "$FLY_API_TOKEN" ]; then
        echo "ERROR: FLY_API_TOKEN environment variable is not set" >&2
        return 1
    fi

    # Construct the full image name
    local image="n8nio/n8n:${version}"

    echo "INFO: Deploying $image to $app_name..." >&2

    # Execute deployment using flyctl
    # The --image flag updates only the Docker image while preserving all other configuration
    local deploy_output
    deploy_output=$(flyctl deploy --app "$app_name" --image "$image" 2>&1)
    local exit_code=$?

    # Check if deployment failed
    if [ $exit_code -ne 0 ]; then
        echo "ERROR: Deployment failed with exit code $exit_code" >&2
        echo "$deploy_output" >&2
        log_deployment_failure "$version" "$deploy_output"
        return 1
    fi

    echo "INFO: Deployment completed successfully" >&2
    echo "$deploy_output" >&2
    log_deployment_success "$version"

    return 0
}

# Fetch release notes from GitHub API for a specific version
# Args: $1 - version tag (e.g., 1.70.0)
# Returns: Release notes content or empty string if not found
fetch_release_notes() {
    local version="$1"
    local api_url="https://api.github.com/repos/n8n-io/n8n/releases/tags/n8n@${version}"
    local response
    local http_code

    # Make API request
    response=$(curl -s -w "\n%{http_code}" "$api_url" 2>&1)
    http_code=$(echo "$response" | tail -n1)
    response=$(echo "$response" | sed '$d')

    # Check HTTP status code
    if [ "$http_code" != "200" ]; then
        return 1
    fi

    # Extract release body (release notes)
    echo "$response" | jq -r '.body // empty' 2>/dev/null
    return 0
}

# Get release notes directly from GitHub for a version
# This is a simpler approach that just fetches the release notes for the target version
# without needing to query Docker Hub again
# Args: $1 - version tag (e.g., 1.70.0)
# Returns: Formatted release notes or error message
get_release_notes_safe() {
    local version="$1"
    local notes

    notes=$(fetch_release_notes "$version")

    if [ -z "$notes" ]; then
        echo "Release notes not available for version ${version}"
        return 1
    fi

    echo "$notes"
    return 0
}

# Format release notes into a concise summary
# Input: raw release notes via stdin
# Returns: Formatted summary with key highlights
format_release_summary() {
    # Read from stdin
    local notes
    notes=$(cat)

    if [ -z "$notes" ]; then
        echo "No release notes available"
        return
    fi

    # Extract key sections and format nicely
    # Remove HTML comments, clean up markdown
    echo "$notes" | \
        sed 's/<!--.*-->//g' | \
        sed 's/\r//g' | \
        head -50
}

# Fetch changelog summary for the target version only
# This simplified version only fetches notes for the version being deployed
# Args: $1 - current version, $2 - latest version
# Returns: Formatted changelog summary
fetch_changelog_summary() {
    local current_version="$1"
    local latest_version="$2"

    echo "🔍 Fetching release notes for v${latest_version}..." >&2

    # Fetch release notes for the target version
    local notes
    notes=$(fetch_release_notes "$latest_version")

    if [ -z "$notes" ]; then
        echo "📝 Release notes not available for version ${latest_version}."
        echo ""
        echo "View all releases: https://github.com/n8n-io/n8n/releases"
        return
    fi

    # Format and output the release notes
    local formatted
    formatted=$(echo "$notes" | format_release_summary)

    echo "### 🏷️ Version ${latest_version}"
    echo ""
    echo "$formatted"
    echo ""
    echo "---"
    echo "📋 *For older versions, see [full changelog](https://github.com/n8n-io/n8n/releases)*"
}

# Create a nicely formatted version update summary for GitHub Actions
# Args: $1 - current version, $2 - latest version
# Outputs: Markdown formatted summary to GITHUB_STEP_SUMMARY
create_version_summary() {
    local current_version="$1"
    local latest_version="$2"

    if [ -z "$latest_version" ]; then
        return
    fi

    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "           📝 Fetching Version Update Summary                      " >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2

    # Fetch the changelog
    local changelog
    changelog=$(fetch_changelog_summary "$current_version" "$latest_version")

    # Output to GitHub Actions summary if available
    if [ -n "$GITHUB_STEP_SUMMARY" ]; then
        {
            echo ""
            echo "## 📝 What's New"
            echo ""
            if [ -z "$current_version" ]; then
                echo "> 🎉 **Initial deployment** to version **${latest_version}**"
            else
                echo "> 📦 Upgrading from **${current_version}** → **${latest_version}**"
            fi
            echo ""
            echo "<details>"
            echo "<summary>📋 Click to view release notes</summary>"
            echo ""
            echo "$changelog"
            echo ""
            echo "</details>"
            echo ""
            echo "---"
            echo ""
            echo "🔗 **Useful Links:**"
            echo "- [n8n Releases](https://github.com/n8n-io/n8n/releases)"
            echo "- [n8n Changelog](https://docs.n8n.io/reference/release-notes/)"
            echo "- [n8n Documentation](https://docs.n8n.io/)"
            echo ""
        } >> "$GITHUB_STEP_SUMMARY"
    fi

    # Also output to console
    echo "" >&2
    echo "📝 Version Update Summary:" >&2
    if [ -z "$current_version" ]; then
        echo "   🎉 Initial deployment to version ${latest_version}" >&2
    else
        echo "   📦 ${current_version} → ${latest_version}" >&2
    fi
    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
}

# Verify deployment health after deployment
# Args: $1 - app name
# Returns: 0 if healthy, non-zero if unhealthy
# Requires: FLY_API_TOKEN environment variable
verify_deployment_health() {
    local app_name="$1"

    if [ -z "$app_name" ]; then
        echo "ERROR: App name is required for health verification" >&2
        return 1
    fi

    # Check if FLY_API_TOKEN is set
    if [ -z "$FLY_API_TOKEN" ]; then
        echo "ERROR: FLY_API_TOKEN environment variable is not set" >&2
        return 1
    fi

    echo "INFO: Verifying deployment health for $app_name..." >&2

    # Query app status to check health
    local status_output
    status_output=$(flyctl status --app "$app_name" --json 2>&1)
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        echo "ERROR: Failed to query app status" >&2
        echo "$status_output" >&2
        return 1
    fi

    # Parse status to check if app is running
    local status
    status=$(echo "$status_output" | jq -r '.Status // empty' 2>/dev/null)

    if [ -z "$status" ]; then
        # Try alternative status field
        status=$(echo "$status_output" | jq -r '.Machines[0].state // empty' 2>/dev/null)
    fi

    # Check if any machines are running
    local running_machines
    running_machines=$(echo "$status_output" | jq '[.Machines[]? | select(.state == "started" or .state == "running")] | length' 2>/dev/null)

    if [ "$running_machines" -gt 0 ]; then
        echo "INFO: Deployment is healthy - $running_machines machine(s) running" >&2
        return 0
    fi

    echo "ERROR: No healthy machines found" >&2
    return 1
}
