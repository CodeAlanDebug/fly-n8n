#!/bin/bash
#
# Pure version logic: filtering, comparison, semver parsing, the deploy
# decision, and the fly.toml read/write that pins an explicit version. No
# network or Fly access - this is the most heavily tested module.

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
