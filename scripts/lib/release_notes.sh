#!/bin/bash
#
# Release notes: fetch n8n's GitHub release notes and render a "What's New"
# section for the GitHub Actions step summary. Always non-critical - the deploy
# workflow runs this with continue-on-error.

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
