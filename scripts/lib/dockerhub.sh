#!/bin/bash
#
# Docker Hub access: fetch and extract n8n image tags.

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
