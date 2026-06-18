#!/bin/bash
#
# Fly.io access via flyctl: read the deployed version, deploy, verify health.
# Every function requires FLY_API_TOKEN and must never echo it.
#
# NOTE: query_flyio_version is currently unused - the deploy workflow reads the
# current version from fly.toml (see read_pinned_version) to avoid the ':latest'
# trap. It is kept (and tested) as it may be useful for diagnostics.

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
