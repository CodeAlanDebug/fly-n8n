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
    echo "╔════════════════════════════════════════╗" >&2
    echo "║     n8n Auto-Deploy Workflow Summary    ║" >&2
    echo "╠════════════════════════════════════════╣" >&2
    echo "║ Action: $action" >&2
    echo "║ Current version: ${current_version:-not deployed}" >&2
    echo "║ Latest version: ${latest_version:-unknown}" >&2
    echo "╚════════════════════════════════════════╝" >&2
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

    # Parse image from JSON output
    local image
    image=$(echo "$status_output" | jq -r '.Image // empty' 2>/dev/null)

    if [ -z "$image" ]; then
        echo "WARNING: No image found in Fly.io status" >&2
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
