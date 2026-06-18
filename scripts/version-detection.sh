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

# Check whether a string is a strict X.Y.Z semantic version
# Args: $1 - candidate string
# Returns: 0 if it is a semver, 1 otherwise
is_semver() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# Extract the major component of a semantic version
# Args: $1 - version (e.g. 2.27.1)
# Returns: major number (e.g. 2)
major_of() {
    echo "${1%%.*}"
}

# Resolve the version that n8n's ':latest' tag currently points to, by digest.
# n8n promotes a specific stable release to ':latest'; we deploy the matching
# explicit X.Y.Z tag (never ':latest' itself, which would re-create the trap).
# Args: $1 - JSON response from query_dockerhub_tags
# Returns: the highest stable version tag sharing ':latest's digest, or empty
resolve_latest_version() {
    local json="$1"
    local latest_digest
    latest_digest=$(echo "$json" \
        | jq -r '.results[]? | select(.name == "latest") | .digest // empty' 2>/dev/null \
        | head -1)

    [ -z "$latest_digest" ] && return 0

    echo "$json" \
        | jq -r --arg d "$latest_digest" '.results[]? | select(.digest == $d) | .name' 2>/dev/null \
        | filter_stable_versions \
        | find_latest_version
}

# Read the pinned n8n version from fly.toml's [build] image line.
# fly.toml is the single source of truth for the deployed version; the Fly
# deploy-on-push trigger deploys whatever tag is pinned here.
# Args: $1 - path to fly.toml (default: fly.toml)
# Returns: the version tag (e.g. 2.27.1), or empty if the image is untagged
read_pinned_version() {
    local flytoml="${1:-fly.toml}"
    local image
    image=$(grep -E "^[[:space:]]*image[[:space:]]*=" "$flytoml" 2>/dev/null \
        | head -1 \
        | sed -E "s/.*=[[:space:]]*['\"]([^'\"]+)['\"].*/\1/")
    parse_version_from_image "$image"
}

# Rewrite fly.toml's [build] image line to pin a specific n8n version,
# preserving the original indentation.
# Args: $1 - path to fly.toml, $2 - version tag to pin
bump_flytoml_image() {
    local flytoml="$1"
    local version="$2"
    # -i.bak then rm keeps this portable across GNU sed (Linux/CI) and BSD sed (macOS)
    sed -i.bak -E "s|^([[:space:]]*image[[:space:]]*=[[:space:]]*).*|\1'n8nio/n8n:${version}'|" "$flytoml"
    rm -f "${flytoml}.bak"
}

# Parse the version tag out of a container image reference.
# Handles repo:tag, registry/host:port style refs, and an optional @sha256
# digest suffix. A pure digest (no tag) returns empty - the version is unknown,
# which is what lets the caller decide to re-pin to an explicit tag.
# Args: $1 - image reference (e.g. n8nio/n8n:2.27.1)
# Returns: the tag (e.g. 2.27.1), or empty if the ref carries no tag
parse_version_from_image() {
    local image="$1"
    [ -z "$image" ] && return 0

    # Drop any "@sha256:..." digest suffix; what remains is repo[:tag]
    local ref="${image%@*}"

    # Look only at the final path segment so a registry host:port is never
    # mistaken for a tag (e.g. "host:5000/n8n" has no tag)
    local last="${ref##*/}"

    case "$last" in
        *:*) echo "${last##*:}" ;;
        *)   return 0 ;;
    esac
}

# Keep only versions belonging to a given major series
# Args: $1 - major number. Versions via stdin, one per line.
# Returns: matching versions, one per line
filter_major() {
    local major="$1"
    while IFS= read -r version; do
        [ -z "$version" ] && continue
        if [ "$(major_of "$version")" = "$major" ]; then
            echo "$version"
        fi
    done
}

# Compare two semantic versions
# Args: $1 - version1, $2 - version2
# Returns: 0 if version1 > version2, 1 if version1 <= version2
version_greater_than() {
    local v1="$1"
    local v2="$2"

    # Non-semver inputs (e.g. a floating 'latest' tag or an image digest)
    # cannot be ordered numerically. Treat them as "not greater" instead of
    # letting the integer comparisons below error out on bad input.
    if ! is_semver "$v1" || ! is_semver "$v2"; then
        return 1
    fi

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
    version_tag=$(parse_version_from_image "$image")

    if [ -z "$version_tag" ]; then
        echo "WARNING: Could not extract a version tag from image: $image" >&2
        echo "         (image is pinned by digest, so the running version is" >&2
        echo "          unknown - the next deploy will re-pin it to a tag)" >&2
        return 0
    fi

    # Record what we resolved so a stuck/looping state is visible in the logs
    echo "INFO: Resolved running version '$version_tag' from image '$image'" >&2

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

    # If the deployed tag is not a strict semver (e.g. a floating 'latest' tag
    # or an image digest), we cannot reason about it - pin it to the explicit
    # target version so subsequent runs can compare normally.
    if ! is_semver "$current_version"; then
        return 0
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
    local curl_error

    # Make API request - capture stderr separately for error logging
    curl_error=$(mktemp -t curl_error.XXXXXX)
    response=$(curl -s -w "\n%{http_code}" "$api_url" 2>"$curl_error")
    local curl_exit_code=$?

    # Log curl errors if any occurred
    if [ $curl_exit_code -ne 0 ]; then
        echo "ERROR: curl failed with exit code $curl_exit_code" >&2
        if [ -s "$curl_error" ]; then
            echo "curl error: $(cat "$curl_error")" >&2
        fi
        rm -f "$curl_error"
        return 1
    fi
    rm -f "$curl_error"

    http_code=$(echo "$response" | tail -n1)
    response=$(echo "$response" | sed '$d')

    # Check HTTP status code
    if [ "$http_code" != "200" ]; then
        echo "WARNING: GitHub API returned HTTP $http_code for version $version" >&2
        return 1
    fi

    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        echo "ERROR: jq is required but not installed" >&2
        return 1
    fi

    # Extract release body (release notes) - log jq errors for debugging
    local jq_error
    jq_error=$(mktemp -t jq_error.XXXXXX)
    local body
    body=$(echo "$response" | jq -r '.body // empty' 2>"$jq_error")

    if [ -s "$jq_error" ]; then
        echo "WARNING: jq parsing issue: $(cat "$jq_error")" >&2
    fi
    rm -f "$jq_error"

    echo "$body"
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
    # Remove HTML comments (using non-greedy match to handle multiple comments per line)
    # Clean up markdown and limit to 50 lines to keep the GitHub Actions summary readable
    # (n8n release notes are typically 20-100+ lines, 50 captures key changes)
    echo "$notes" | \
        perl -pe 's/<!--.*?-->//g' | \
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
