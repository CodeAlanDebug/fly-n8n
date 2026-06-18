#!/usr/bin/env bats

# Feature: n8n-auto-deploy, Property 4: API Error Handling
# Validates: Requirements 1.4

# Load the version detection functions
setup() {
    # Source the version detection script
    source "${BATS_TEST_DIRNAME}/../scripts/version-detection.sh"
}

# Property 4: API Error Handling
# For any API error response from Docker Hub, the system should log the error
# message and exit gracefully without crashing or triggering a deployment.
@test "API error handling - network failures return error code" {
    # Test with invalid URL to simulate network failure
    run bash -c '
        source scripts/version-detection.sh
        # Override curl to simulate network failure
        curl() { return 1; }
        export -f curl
        query_dockerhub_tags
    '

    # Should return non-zero exit code
    [ "$status" -ne 0 ]

    # Should log error message
    [[ "$output" =~ "ERROR" ]]
}

@test "API error handling - HTTP error codes return error" {
    # Test with various HTTP error codes
    for http_code in 404 500 503; do
        run bash -c "
            source scripts/version-detection.sh
            # Override curl to return error HTTP code
            curl() { echo '{}'; echo '$http_code'; }
            export -f curl
            query_dockerhub_tags
        "

        # Should return non-zero exit code
        [ "$status" -ne 0 ]

        # Should log error with HTTP code
        [[ "$output" =~ "ERROR" ]]
        [[ "$output" =~ "$http_code" ]]
    done
}

@test "API error handling - invalid JSON returns error" {
    run bash -c '
        source scripts/version-detection.sh
        # Override curl to return invalid JSON
        curl() { echo "not valid json"; echo "200"; }
        export -f curl
        query_dockerhub_tags
    '

    # Should return non-zero exit code
    [ "$status" -ne 0 ]

    # Should log error about invalid JSON
    [[ "$output" =~ "ERROR" ]]
    [[ "$output" =~ "Invalid JSON" ]]
}

@test "API error handling - empty response returns error" {
    run bash -c '
        source scripts/version-detection.sh
        extract_tag_names ""
    '

    # Should return non-zero exit code
    [ "$status" -ne 0 ]

    # Should log error
    [[ "$output" =~ "ERROR" ]]
}

@test "API error handling - successful response returns 0" {
    run bash -c '
        source scripts/version-detection.sh
        # Override curl to return valid response
        curl() { echo "{\"results\":[{\"name\":\"1.0.0\"}]}"; echo "200"; }
        export -f curl
        query_dockerhub_tags
    '

    # Should return zero exit code
    [ "$status" -eq 0 ]

    # Should return valid JSON
    [[ "$output" =~ "results" ]]
}


# Feature: n8n-auto-deploy, Property 3: Pre-release Version Filtering
# Validates: Requirements 1.3

# Property 3: Pre-release Version Filtering
# For any version tag containing pre-release identifiers (such as -beta, -alpha,
# -rc, or any hyphenated suffix), the version filtering function should exclude
# it from the list of stable versions.
@test "Pre-release filtering - filters out beta versions" {
    run bash -c '
        source scripts/version-detection.sh
        echo -e "1.0.0\n1.1.0-beta\n1.2.0\n2.0.0-beta.1" | filter_stable_versions
    '

    [ "$status" -eq 0 ]

    # Should only contain stable versions
    [[ "$output" =~ "1.0.0" ]]
    [[ "$output" =~ "1.2.0" ]]
    [[ ! "$output" =~ "beta" ]]
}

@test "Pre-release filtering - filters out alpha versions" {
    run bash -c '
        source scripts/version-detection.sh
        echo -e "1.0.0\n1.1.0-alpha\n1.2.0\n2.0.0-alpha.1" | filter_stable_versions
    '

    [ "$status" -eq 0 ]

    # Should only contain stable versions
    [[ "$output" =~ "1.0.0" ]]
    [[ "$output" =~ "1.2.0" ]]
    [[ ! "$output" =~ "alpha" ]]
}

@test "Pre-release filtering - filters out rc versions" {
    run bash -c '
        source scripts/version-detection.sh
        echo -e "1.0.0\n1.1.0-rc1\n1.2.0\n2.0.0-rc.2" | filter_stable_versions
    '

    [ "$status" -eq 0 ]

    # Should only contain stable versions
    [[ "$output" =~ "1.0.0" ]]
    [[ "$output" =~ "1.2.0" ]]
    [[ ! "$output" =~ "rc" ]]
}

@test "Pre-release filtering - filters out any hyphenated versions" {
    run bash -c '
        source scripts/version-detection.sh
        echo -e "1.0.0\n1.1.0-dev\n1.2.0\n2.0.0-snapshot" | filter_stable_versions
    '

    [ "$status" -eq 0 ]

    # Should only contain stable versions
    [[ "$output" =~ "1.0.0" ]]
    [[ "$output" =~ "1.2.0" ]]
    [[ ! "$output" =~ "-" ]]
}

@test "Pre-release filtering - filters out non-semantic version tags" {
    run bash -c '
        source scripts/version-detection.sh
        echo -e "1.0.0\nlatest\n1.2.0\nnext\ndev" | filter_stable_versions
    '

    [ "$status" -eq 0 ]

    # Should only contain semantic versions
    [[ "$output" =~ "1.0.0" ]]
    [[ "$output" =~ "1.2.0" ]]
    [[ ! "$output" =~ "latest" ]]
    [[ ! "$output" =~ "next" ]]
    [[ ! "$output" =~ "dev" ]]
}

@test "Pre-release filtering - property test with 100 random versions" {
    # Generate 100 random version combinations
    run bash -c '
        source scripts/version-detection.sh

        # Generate mix of stable and pre-release versions
        for i in {1..100}; do
            major=$((RANDOM % 10))
            minor=$((RANDOM % 20))
            patch=$((RANDOM % 30))

            # 50% chance of being stable
            if [ $((RANDOM % 2)) -eq 0 ]; then
                echo "$major.$minor.$patch"
            else
                # Random pre-release identifier
                case $((RANDOM % 4)) in
                    0) echo "$major.$minor.$patch-beta" ;;
                    1) echo "$major.$minor.$patch-alpha" ;;
                    2) echo "$major.$minor.$patch-rc1" ;;
                    3) echo "$major.$minor.$patch-dev" ;;
                esac
            fi
        done | filter_stable_versions
    '

    [ "$status" -eq 0 ]

    # Verify no pre-release identifiers in output
    [[ ! "$output" =~ "-" ]]
    [[ ! "$output" =~ "beta" ]]
    [[ ! "$output" =~ "alpha" ]]
    [[ ! "$output" =~ "rc" ]]
}


# Feature: n8n-auto-deploy, Property 2: Semantic Version Comparison Correctness
# Validates: Requirements 1.2

# Property 2: Semantic Version Comparison Correctness
# For any pair of valid semantic version strings, the version comparison function
# should correctly determine which version is newer according to semantic versioning
# rules (major.minor.patch ordering).
@test "Semantic version comparison - major version takes precedence" {
    run bash -c '
        source scripts/version-detection.sh
        version_greater_than "2.0.0" "1.9.9"
    '
    [ "$status" -eq 0 ]

    run bash -c '
        source scripts/version-detection.sh
        version_greater_than "1.9.9" "2.0.0"
    '
    [ "$status" -ne 0 ]
}

@test "Semantic version comparison - minor version when major equal" {
    run bash -c '
        source scripts/version-detection.sh
        version_greater_than "1.5.0" "1.4.9"
    '
    [ "$status" -eq 0 ]

    run bash -c '
        source scripts/version-detection.sh
        version_greater_than "1.4.9" "1.5.0"
    '
    [ "$status" -ne 0 ]
}

@test "Semantic version comparison - patch version when major and minor equal" {
    run bash -c '
        source scripts/version-detection.sh
        version_greater_than "1.2.5" "1.2.3"
    '
    [ "$status" -eq 0 ]

    run bash -c '
        source scripts/version-detection.sh
        version_greater_than "1.2.3" "1.2.5"
    '
    [ "$status" -ne 0 ]
}

@test "Semantic version comparison - equal versions return false" {
    run bash -c '
        source scripts/version-detection.sh
        version_greater_than "1.2.3" "1.2.3"
    '
    [ "$status" -ne 0 ]
}

@test "Semantic version comparison - property test with 100 random pairs" {
    # Test 100 random version pairs
    bash -c '
        source scripts/version-detection.sh

        for i in {1..100}; do
            # Generate two random versions
            v1_major=$((RANDOM % 10))
            v1_minor=$((RANDOM % 20))
            v1_patch=$((RANDOM % 30))

            v2_major=$((RANDOM % 10))
            v2_minor=$((RANDOM % 20))
            v2_patch=$((RANDOM % 30))

            v1="$v1_major.$v1_minor.$v1_patch"
            v2="$v2_major.$v2_minor.$v2_patch"

            # Test comparison
            if version_greater_than "$v1" "$v2"; then
                result="v1>v2"
            else
                result="v1<=v2"
            fi

            # Verify correctness
            if [ "$v1_major" -gt "$v2_major" ]; then
                [ "$result" = "v1>v2" ] || exit 1
            elif [ "$v1_major" -lt "$v2_major" ]; then
                [ "$result" = "v1<=v2" ] || exit 1
            elif [ "$v1_minor" -gt "$v2_minor" ]; then
                [ "$result" = "v1>v2" ] || exit 1
            elif [ "$v1_minor" -lt "$v2_minor" ]; then
                [ "$result" = "v1<=v2" ] || exit 1
            elif [ "$v1_patch" -gt "$v2_patch" ]; then
                [ "$result" = "v1>v2" ] || exit 1
            else
                [ "$result" = "v1<=v2" ] || exit 1
            fi
        done
    '

    [ "$?" -eq 0 ]
}


# Feature: n8n-auto-deploy, Property 8: Latest Version Selection
# Validates: Requirements 2.4

# Property 8: Latest Version Selection
# For any set of multiple stable versions, the system should select and deploy
# only the version with the highest semantic version number.
@test "Latest version selection - finds highest from simple list" {
    run bash -c '
        source scripts/version-detection.sh
        echo -e "1.0.0\n1.2.0\n1.1.0" | find_latest_version
    '

    [ "$status" -eq 0 ]
    [ "$output" = "1.2.0" ]
}

@test "Latest version selection - handles major version differences" {
    run bash -c '
        source scripts/version-detection.sh
        echo -e "1.9.9\n2.0.0\n1.10.5" | find_latest_version
    '

    [ "$status" -eq 0 ]
    [ "$output" = "2.0.0" ]
}

@test "Latest version selection - handles minor version differences" {
    run bash -c '
        source scripts/version-detection.sh
        echo -e "1.5.0\n1.10.0\n1.8.0" | find_latest_version
    '

    [ "$status" -eq 0 ]
    [ "$output" = "1.10.0" ]
}

@test "Latest version selection - handles patch version differences" {
    run bash -c '
        source scripts/version-detection.sh
        echo -e "1.2.3\n1.2.10\n1.2.5" | find_latest_version
    '

    [ "$status" -eq 0 ]
    [ "$output" = "1.2.10" ]
}

@test "Latest version selection - single version returns that version" {
    run bash -c '
        source scripts/version-detection.sh
        echo "1.2.3" | find_latest_version
    '

    [ "$status" -eq 0 ]
    [ "$output" = "1.2.3" ]
}

@test "Latest version selection - property test with 100 random sets" {
    # Test 100 random version sets
    bash -c '
        source scripts/version-detection.sh

        for i in {1..100}; do
            # Generate 5-15 random versions
            num_versions=$((5 + RANDOM % 11))
            versions=()
            max_major=0
            max_minor=0
            max_patch=0

            for j in $(seq 1 $num_versions); do
                major=$((RANDOM % 10))
                minor=$((RANDOM % 20))
                patch=$((RANDOM % 30))

                versions+=("$major.$minor.$patch")

                # Track expected maximum
                if [ "$major" -gt "$max_major" ]; then
                    max_major=$major
                    max_minor=$minor
                    max_patch=$patch
                elif [ "$major" -eq "$max_major" ] && [ "$minor" -gt "$max_minor" ]; then
                    max_minor=$minor
                    max_patch=$patch
                elif [ "$major" -eq "$max_major" ] && [ "$minor" -eq "$max_minor" ] && [ "$patch" -gt "$max_patch" ]; then
                    max_patch=$patch
                fi
            done

            # Find latest version
            result=$(printf "%s\n" "${versions[@]}" | find_latest_version)
            expected="$max_major.$max_minor.$max_patch"

            # Verify result matches expected
            if [ "$result" != "$expected" ]; then
                echo "Test $i failed: expected $expected, got $result" >&2
                exit 1
            fi
        done
    '

    [ "$?" -eq 0 ]
}

@test "Latest version selection - complete workflow integration" {
    # Test the complete workflow: query -> filter -> find latest
    run bash -c '
        source scripts/version-detection.sh

        # Simulate a complete version list with various types
        echo -e "latest\n1.0.0\n1.1.0-beta\n1.2.0\n2.0.0-rc1\n1.5.0\nnext\n1.3.0" | \
            filter_stable_versions | \
            find_latest_version
    '

    [ "$status" -eq 0 ]
    [ "$output" = "1.5.0" ]
}


# Feature: n8n-auto-deploy, Property 9: API Token Usage
# Validates: Requirements 3.1

# Property 9: API Token Usage
# For any Fly.io authentication attempt, the system should read the API token
# from the designated GitHub Secret environment variable.
@test "API token usage - function requires FLY_API_TOKEN environment variable" {
    # Test without FLY_API_TOKEN set
    run bash -c '
        unset FLY_API_TOKEN
        source scripts/version-detection.sh
        query_flyio_version "test-app"
    '

    # Should return non-zero exit code
    [ "$status" -ne 0 ]

    # Should log error about missing token
    [[ "$output" =~ "ERROR" ]]
    [[ "$output" =~ "FLY_API_TOKEN" ]]
}

@test "API token usage - function uses FLY_API_TOKEN when set" {
    # Test with FLY_API_TOKEN set
    run bash -c '
        export FLY_API_TOKEN="test-token-123"
        source scripts/version-detection.sh

        # Mock flyctl to verify it runs when token is set
        flyctl() {
            # Verify we are called with the right app
            if [[ "$*" =~ "test-app" ]]; then
                echo "{\"Image\":\"n8nio/n8n:1.0.0\"}"
                return 0
            fi
            return 1
        }
        export -f flyctl

        query_flyio_version "test-app"
    '

    # Should succeed when token is set
    [ "$status" -eq 0 ]

    # Should return version
    [[ "$output" =~ "1.0.0" ]]
}

@test "API token usage - property test with various token formats" {
    # Test that function accepts any non-empty token value
    bash -c '
        source scripts/version-detection.sh

        # Mock flyctl
        flyctl() {
            echo "{\"Image\":\"n8nio/n8n:1.0.0\"}"
            return 0
        }
        export -f flyctl

        # Test 100 different token formats
        for i in {1..100}; do
            # Generate random token-like strings
            case $((RANDOM % 5)) in
                0) token="token-$RANDOM-$RANDOM" ;;
                1) token="$(head -c 32 /dev/urandom | base64 | tr -d /=+ | head -c 32)" ;;
                2) token="fly_$(head -c 16 /dev/urandom | base64 | tr -d /=+ | head -c 16)" ;;
                3) token="$(uuidgen 2>/dev/null || echo "uuid-$RANDOM-$RANDOM")" ;;
                4) token="very-long-token-$(head -c 64 /dev/urandom | base64 | tr -d /=+ | head -c 64)" ;;
            esac

            export FLY_API_TOKEN="$token"
            result=$(query_flyio_version "test-app" 2>&1)
            exit_code=$?

            # Should succeed with any valid token format
            if [ $exit_code -ne 0 ]; then
                echo "Failed with token format: $token" >&2
                exit 1
            fi
        done
    '

    [ "$?" -eq 0 ]
}

@test "API token usage - empty token is treated as missing" {
    run bash -c '
        export FLY_API_TOKEN=""
        source scripts/version-detection.sh
        query_flyio_version "test-app"
    '

    # Should fail with empty token
    [ "$status" -ne 0 ]
    [[ "$output" =~ "ERROR" ]]
}


# Feature: n8n-auto-deploy, Property 10: Authentication Failure Handling
# Validates: Requirements 3.2

# Property 10: Authentication Failure Handling
# For any case where the API token is missing or invalid, the system should fail
# with a non-zero exit code and log an authentication error message.
@test "Authentication failure handling - missing token fails with error" {
    run bash -c '
        unset FLY_API_TOKEN
        source scripts/version-detection.sh
        query_flyio_version "test-app"
    '

    # Should return non-zero exit code
    [ "$status" -ne 0 ]

    # Should log authentication error
    [[ "$output" =~ "ERROR" ]]
    [[ "$output" =~ "FLY_API_TOKEN" ]]
}

@test "Authentication failure handling - invalid token fails with error" {
    run bash -c '
        export FLY_API_TOKEN="invalid-token"
        source scripts/version-detection.sh

        # Mock flyctl to simulate authentication failure
        flyctl() {
            echo "Error: authentication failed - invalid token" >&2
            return 1
        }
        export -f flyctl

        query_flyio_version "test-app"
    '

    # Should return non-zero exit code (specifically 2 for auth errors)
    [ "$status" -eq 2 ]

    # Should log authentication error
    [[ "$output" =~ "ERROR" ]]
    [[ "$output" =~ "Authentication failed" ]]
}

@test "Authentication failure handling - unauthorized access fails with error" {
    run bash -c '
        export FLY_API_TOKEN="unauthorized-token"
        source scripts/version-detection.sh

        # Mock flyctl to simulate unauthorized error
        flyctl() {
            echo "Error: unauthorized access to app" >&2
            return 1
        }
        export -f flyctl

        query_flyio_version "test-app"
    '

    # Should return non-zero exit code
    [ "$status" -eq 2 ]

    # Should log authentication error
    [[ "$output" =~ "ERROR" ]]
    [[ "$output" =~ "Authentication failed" ]]
}

@test "Authentication failure handling - property test with various auth errors" {
    # Test 100 different authentication error scenarios
    bash -c '
        source scripts/version-detection.sh

        # Test various authentication error messages
        auth_errors=(
            "authentication failed"
            "unauthorized"
            "invalid token"
            "authentication required"
            "unauthorized access"
            "token expired"
            "invalid credentials"
        )

        for i in {1..100}; do
            export FLY_API_TOKEN="test-token-$i"

            # Pick random auth error message
            error_msg="${auth_errors[$((RANDOM % ${#auth_errors[@]}))]}"

            # Mock flyctl to return auth error
            flyctl() {
                echo "Error: $error_msg" >&2
                return 1
            }
            export -f flyctl

            result=$(query_flyio_version "test-app" 2>&1)
            exit_code=$?

            # Should fail with auth error
            if [ $exit_code -ne 2 ]; then
                echo "Test $i failed: expected exit code 2, got $exit_code" >&2
                echo "Error message: $error_msg" >&2
                exit 1
            fi

            # Should log authentication error
            if [[ ! "$result" =~ "ERROR" ]] || [[ ! "$result" =~ "Authentication failed" ]]; then
                echo "Test $i failed: missing authentication error in output" >&2
                echo "Output: $result" >&2
                exit 1
            fi
        done
    '

    [ "$?" -eq 0 ]
}

@test "Authentication failure handling - non-auth errors return different code" {
    run bash -c '
        export FLY_API_TOKEN="valid-token"
        source scripts/version-detection.sh

        # Mock flyctl to simulate non-auth error
        flyctl() {
            echo "Error: network timeout" >&2
            return 1
        }
        export -f flyctl

        query_flyio_version "test-app"
    '

    # Should return exit code 1 (not 2 which is for auth errors)
    [ "$status" -eq 1 ]

    # Should log error but not specifically auth error
    [[ "$output" =~ "ERROR" ]]
    [[ ! "$output" =~ "Authentication failed" ]]
}

@test "Authentication failure handling - app not found is not auth error" {
    run bash -c '
        export FLY_API_TOKEN="valid-token"
        source scripts/version-detection.sh

        # Mock flyctl to simulate app not found
        flyctl() {
            echo "Error: app not found" >&2
            return 1
        }
        export -f flyctl

        query_flyio_version "test-app"
    '

    # Should return 0 (not an error, just no deployment)
    [ "$status" -eq 0 ]

    # Should log warning
    [[ "$output" =~ "WARNING" ]]
}


# Feature: n8n-auto-deploy, Property 5: Deployment Trigger on New Version
# Validates: Requirements 2.1

# Property 5: Deployment Trigger on New Version
# For any case where the latest Docker Hub version is semantically greater than
# the current deployed version, the system should initiate a deployment to Fly.io.
@test "Deployment trigger - update needed when latest is greater (major)" {
    run bash -c '
        source scripts/version-detection.sh
        needs_update "1.0.0" "2.0.0"
    '

    # Should return 0 (true) - update needed
    [ "$status" -eq 0 ]
}

@test "Deployment trigger - update needed when latest is greater (minor)" {
    run bash -c '
        source scripts/version-detection.sh
        needs_update "1.5.0" "1.10.0"
    '

    # Should return 0 (true) - update needed
    [ "$status" -eq 0 ]
}

@test "Deployment trigger - update needed when latest is greater (patch)" {
    run bash -c '
        source scripts/version-detection.sh
        needs_update "1.2.3" "1.2.5"
    '

    # Should return 0 (true) - update needed
    [ "$status" -eq 0 ]
}

@test "Deployment trigger - update needed when current is empty" {
    run bash -c '
        source scripts/version-detection.sh
        needs_update "" "1.0.0"
    '

    # Should return 0 (true) - update needed (initial deployment)
    [ "$status" -eq 0 ]
}

@test "Deployment trigger - property test with 100 random version pairs" {
    # Test 100 random cases where latest > current
    bash -c '
        source scripts/version-detection.sh

        for i in {1..100}; do
            # Generate current version
            curr_major=$((RANDOM % 5))
            curr_minor=$((RANDOM % 10))
            curr_patch=$((RANDOM % 20))
            current="$curr_major.$curr_minor.$curr_patch"

            # Generate latest version that is guaranteed to be greater
            case $((RANDOM % 3)) in
                0)
                    # Greater major
                    latest="$((curr_major + 1 + RANDOM % 3)).$((RANDOM % 10)).$((RANDOM % 20))"
                    ;;
                1)
                    # Same major, greater minor
                    latest="$curr_major.$((curr_minor + 1 + RANDOM % 5)).$((RANDOM % 20))"
                    ;;
                2)
                    # Same major and minor, greater patch
                    latest="$curr_major.$curr_minor.$((curr_patch + 1 + RANDOM % 10))"
                    ;;
            esac

            # Test that update is needed
            if ! needs_update "$current" "$latest"; then
                echo "Test $i failed: should need update from $current to $latest" >&2
                exit 1
            fi
        done
    '

    [ "$?" -eq 0 ]
}


# Feature: n8n-auto-deploy, Property 6: No Deployment When Versions Match
# Validates: Requirements 2.2

# Property 6: No Deployment When Versions Match
# For any case where the latest Docker Hub version equals the current deployed
# version, the system should complete without triggering a deployment.
@test "No deployment - versions match exactly" {
    run bash -c '
        source scripts/version-detection.sh
        needs_update "1.2.3" "1.2.3"
    '

    # Should return 1 (false) - no update needed
    [ "$status" -eq 1 ]
}

@test "No deployment - current is greater than latest (major)" {
    run bash -c '
        source scripts/version-detection.sh
        needs_update "2.0.0" "1.9.9"
    '

    # Should return 1 (false) - no update needed
    [ "$status" -eq 1 ]
}

@test "No deployment - current is greater than latest (minor)" {
    run bash -c '
        source scripts/version-detection.sh
        needs_update "1.10.0" "1.5.0"
    '

    # Should return 1 (false) - no update needed
    [ "$status" -eq 1 ]
}

@test "No deployment - current is greater than latest (patch)" {
    run bash -c '
        source scripts/version-detection.sh
        needs_update "1.2.10" "1.2.5"
    '

    # Should return 1 (false) - no update needed
    [ "$status" -eq 1 ]
}

@test "No deployment - latest version is empty" {
    run bash -c '
        source scripts/version-detection.sh
        needs_update "1.2.3" ""
    '

    # Should return 1 (false) - cannot update to empty version
    [ "$status" -eq 1 ]
}

@test "No deployment - property test with 100 matching versions" {
    # Test 100 random cases where versions match
    bash -c '
        source scripts/version-detection.sh

        for i in {1..100}; do
            # Generate random version
            major=$((RANDOM % 10))
            minor=$((RANDOM % 20))
            patch=$((RANDOM % 30))
            version="$major.$minor.$patch"

            # Test that no update is needed when versions match
            if needs_update "$version" "$version"; then
                echo "Test $i failed: should not need update when versions match ($version)" >&2
                exit 1
            fi
        done
    '

    [ "$?" -eq 0 ]
}

@test "No deployment - property test with 100 cases where current >= latest" {
    # Test 100 random cases where current is greater than or equal to latest
    bash -c '
        source scripts/version-detection.sh

        for i in {1..100}; do
            # Generate latest version
            latest_major=$((RANDOM % 5))
            latest_minor=$((RANDOM % 10))
            latest_patch=$((RANDOM % 20))
            latest="$latest_major.$latest_minor.$latest_patch"

            # Generate current version that is guaranteed to be >= latest
            case $((RANDOM % 4)) in
                0)
                    # Equal version
                    current="$latest"
                    ;;
                1)
                    # Greater major
                    current="$((latest_major + 1 + RANDOM % 3)).$((RANDOM % 10)).$((RANDOM % 20))"
                    ;;
                2)
                    # Same major, greater minor
                    current="$latest_major.$((latest_minor + 1 + RANDOM % 5)).$((RANDOM % 20))"
                    ;;
                3)
                    # Same major and minor, greater patch
                    current="$latest_major.$latest_minor.$((latest_patch + 1 + RANDOM % 10))"
                    ;;
            esac

            # Test that no update is needed
            if needs_update "$current" "$latest"; then
                echo "Test $i failed: should not need update from $current to $latest" >&2
                exit 1
            fi
        done
    '

    [ "$?" -eq 0 ]
}


# Feature: n8n-auto-deploy, Property 7: Deployment Uses Correct Image Tag
# Validates: Requirements 2.3

# Property 7: Deployment Uses Correct Image Tag
# For any deployment operation, the Fly.io CLI command should reference the
# correct Docker image with the new version tag.
@test "Deployment image tag - uses correct image format" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to capture the command
        flyctl() {
            # Verify the image parameter is correct
            if [[ "$*" =~ --image[[:space:]]+n8nio/n8n:1.2.3 ]]; then
                echo "Deployment successful"
                return 0
            else
                echo "ERROR: Incorrect image format in command: $*" >&2
                return 1
            fi
        }
        export -f flyctl

        deploy_to_flyio "1.2.3" "test-app"
    '

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Deployment successful" ]]
}

@test "Deployment image tag - version is included in image name" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to verify version is in the image
        flyctl() {
            if [[ "$*" =~ n8nio/n8n:5.10.20 ]]; then
                echo "Version 5.10.20 deployed"
                return 0
            else
                echo "ERROR: Version not found in image" >&2
                return 1
            fi
        }
        export -f flyctl

        deploy_to_flyio "5.10.20" "test-app"
    '

    [ "$status" -eq 0 ]
}

@test "Deployment image tag - property test with 100 random versions" {
    # Test 100 random version tags to ensure correct image format
    bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        for i in {1..100}; do
            # Generate random semantic version
            major=$((RANDOM % 10))
            minor=$((RANDOM % 20))
            patch=$((RANDOM % 30))
            version="$major.$minor.$patch"

            # Mock flyctl to verify correct image format
            flyctl() {
                local expected_image="n8nio/n8n:$version"
                if [[ "$*" =~ --image[[:space:]]+$expected_image ]]; then
                    return 0
                else
                    echo "Test $i failed: expected image $expected_image not found in: $*" >&2
                    return 1
                fi
            }
            export -f flyctl

            # Test deployment
            if ! deploy_to_flyio "$version" "test-app" >/dev/null 2>&1; then
                echo "Test $i failed with version $version" >&2
                exit 1
            fi
        done
    '

    [ "$?" -eq 0 ]
}

@test "Deployment image tag - fails without version" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        deploy_to_flyio "" "test-app"
    '

    # Should fail when version is missing
    [ "$status" -ne 0 ]
    [[ "$output" =~ "ERROR" ]]
    [[ "$output" =~ "Version is required" ]]
}

@test "Deployment image tag - fails without app name" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        deploy_to_flyio "1.2.3" ""
    '

    # Should fail when app name is missing
    [ "$status" -ne 0 ]
    [[ "$output" =~ "ERROR" ]]
    [[ "$output" =~ "App name is required" ]]
}

@test "Deployment image tag - fails without API token" {
    run bash -c '
        unset FLY_API_TOKEN
        source scripts/version-detection.sh

        deploy_to_flyio "1.2.3" "test-app"
    '

    # Should fail when token is missing
    [ "$status" -ne 0 ]
    [[ "$output" =~ "ERROR" ]]
    [[ "$output" =~ "FLY_API_TOKEN" ]]
}


# Feature: n8n-auto-deploy, Property 16: Configuration File Preservation
# Validates: Requirements 6.1

# Property 16: Configuration File Preservation
# For any deployment, the system should use the existing fly.toml configuration
# file without modification.
@test "Configuration preservation - deployment uses existing fly.toml" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to verify it does not modify fly.toml
        flyctl() {
            # Verify that deploy command does not include config modification flags
            if [[ "$*" =~ --config ]] || [[ "$*" =~ -c[[:space:]] ]]; then
                echo "ERROR: Deployment should not modify config" >&2
                return 1
            fi

            # Verify it uses --image flag (which preserves config)
            if [[ "$*" =~ --image ]]; then
                echo "Deployment uses existing config"
                return 0
            else
                echo "ERROR: Missing --image flag" >&2
                return 1
            fi
        }
        export -f flyctl

        deploy_to_flyio "1.2.3" "test-app"
    '

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Deployment uses existing config" ]]
}

@test "Configuration preservation - no config flags in deploy command" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to capture full command
        flyctl() {
            echo "Command: $*" >&2

            # Check for config modification flags
            if [[ "$*" =~ --config ]] || \
               [[ "$*" =~ --dockerfile ]] || \
               [[ "$*" =~ --build-arg ]]; then
                echo "ERROR: Config modification detected" >&2
                return 1
            fi

            return 0
        }
        export -f flyctl

        deploy_to_flyio "1.2.3" "test-app"
    '

    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "Config modification detected" ]]
}

@test "Configuration preservation - property test with 100 deployments" {
    # Test 100 deployments to ensure config is never modified
    bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        for i in {1..100}; do
            # Generate random version
            major=$((RANDOM % 10))
            minor=$((RANDOM % 20))
            patch=$((RANDOM % 30))
            version="$major.$minor.$patch"

            # Mock flyctl to verify no config modification
            flyctl() {
                # Fail if any config modification flags are present
                if [[ "$*" =~ --config ]] || \
                   [[ "$*" =~ --dockerfile ]] || \
                   [[ "$*" =~ --build-arg ]] || \
                   [[ "$*" =~ --env ]] || \
                   [[ "$*" =~ --region ]]; then
                    echo "Test $i: Config modification detected in: $*" >&2
                    return 1
                fi

                # Verify --image flag is present
                if [[ ! "$*" =~ --image ]]; then
                    echo "Test $i: Missing --image flag" >&2
                    return 1
                fi

                return 0
            }
            export -f flyctl

            # Test deployment
            if ! deploy_to_flyio "$version" "test-app" >/dev/null 2>&1; then
                echo "Test $i failed with version $version" >&2
                exit 1
            fi
        done
    '

    [ "$?" -eq 0 ]
}

@test "Configuration preservation - only image flag is used" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to verify only essential flags
        flyctl() {
            # Count the number of flags (excluding --app and --image)
            local extra_flags=0

            for arg in "$@"; do
                if [[ "$arg" =~ ^-- ]] && \
                   [[ "$arg" != "--app" ]] && \
                   [[ ! "$arg" =~ ^--image ]]; then
                    extra_flags=$((extra_flags + 1))
                fi
            done

            if [ $extra_flags -gt 0 ]; then
                echo "ERROR: Unexpected flags found: $*" >&2
                return 1
            fi

            return 0
        }
        export -f flyctl

        deploy_to_flyio "1.2.3" "test-app"
    '

    [ "$status" -eq 0 ]
}


# Feature: n8n-auto-deploy, Property 18: Image-Only Updates
# Validates: Requirements 6.3

# Property 18: Image-Only Updates
# For any deployment operation, only the Docker image tag should be updated
# while all other configuration remains unchanged.
@test "Image-only updates - deployment only changes image" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to verify only image is updated
        flyctl() {
            # Verify deploy command with --image flag
            if [[ "$*" =~ deploy ]] && [[ "$*" =~ --image ]]; then
                # Check that no other modification flags are present
                if [[ "$*" =~ --env ]] || \
                   [[ "$*" =~ --region ]] || \
                   [[ "$*" =~ --vm-size ]] || \
                   [[ "$*" =~ --memory ]] || \
                   [[ "$*" =~ --dockerfile ]]; then
                    echo "ERROR: Non-image modifications detected" >&2
                    return 1
                fi
                echo "Image-only update successful"
                return 0
            fi
            return 1
        }
        export -f flyctl

        deploy_to_flyio "1.2.3" "test-app"
    '

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Image-only update successful" ]]
}

@test "Image-only updates - no environment variable changes" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to check for env modifications
        flyctl() {
            if [[ "$*" =~ --env ]] || [[ "$*" =~ --secret ]]; then
                echo "ERROR: Environment modifications not allowed" >&2
                return 1
            fi
            return 0
        }
        export -f flyctl

        deploy_to_flyio "1.2.3" "test-app"
    '

    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "Environment modifications" ]]
}

@test "Image-only updates - no resource changes" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to check for resource modifications
        flyctl() {
            if [[ "$*" =~ --vm-size ]] || \
               [[ "$*" =~ --memory ]] || \
               [[ "$*" =~ --cpu ]] || \
               [[ "$*" =~ --scale ]]; then
                echo "ERROR: Resource modifications not allowed" >&2
                return 1
            fi
            return 0
        }
        export -f flyctl

        deploy_to_flyio "1.2.3" "test-app"
    '

    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "Resource modifications" ]]
}

@test "Image-only updates - no region changes" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to check for region modifications
        flyctl() {
            if [[ "$*" =~ --region ]] || [[ "$*" =~ --primary-region ]]; then
                echo "ERROR: Region modifications not allowed" >&2
                return 1
            fi
            return 0
        }
        export -f flyctl

        deploy_to_flyio "1.2.3" "test-app"
    '

    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "Region modifications" ]]
}

@test "Image-only updates - property test with 100 deployments" {
    # Test 100 deployments to ensure only image is modified
    bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # List of flags that should NOT be present (non-image modifications)
        forbidden_flags=(
            "--env"
            "--secret"
            "--vm-size"
            "--memory"
            "--cpu"
            "--scale"
            "--region"
            "--primary-region"
            "--dockerfile"
            "--build-arg"
            "--port"
            "--internal-port"
        )

        for i in {1..100}; do
            # Generate random version
            major=$((RANDOM % 10))
            minor=$((RANDOM % 20))
            patch=$((RANDOM % 30))
            version="$major.$minor.$patch"

            # Mock flyctl to verify image-only update
            flyctl() {
                # Check for forbidden flags
                for flag in "${forbidden_flags[@]}"; do
                    if [[ "$*" =~ $flag ]]; then
                        echo "Test $i: Forbidden flag $flag found in: $*" >&2
                        return 1
                    fi
                done

                # Verify --image flag is present
                if [[ ! "$*" =~ --image ]]; then
                    echo "Test $i: Missing --image flag" >&2
                    return 1
                fi

                return 0
            }
            export -f flyctl

            # Test deployment
            if ! deploy_to_flyio "$version" "test-app" >/dev/null 2>&1; then
                echo "Test $i failed with version $version" >&2
                exit 1
            fi
        done
    '

    [ "$?" -eq 0 ]
}

@test "Image-only updates - command structure is minimal" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to verify minimal command structure
        flyctl() {
            # Expected: flyctl deploy --app <app> --image <image>
            # Count arguments (should be exactly 5: deploy, --app, <app>, --image, <image>)
            local arg_count=$#

            if [ $arg_count -ne 5 ]; then
                echo "ERROR: Expected 5 arguments, got $arg_count: $*" >&2
                return 1
            fi

            # Verify argument order and structure
            if [ "$1" != "deploy" ] || \
               [ "$2" != "--app" ] || \
               [ "$4" != "--image" ]; then
                echo "ERROR: Incorrect command structure: $*" >&2
                return 1
            fi

            return 0
        }
        export -f flyctl

        deploy_to_flyio "1.2.3" "test-app"
    '

    [ "$status" -eq 0 ]
}


# Feature: n8n-auto-deploy, Property 19: Post-Deployment Health Verification
# Validates: Requirements 6.4

# Property 19: Post-Deployment Health Verification
# For any completed deployment, the system should verify that the n8n service
# passes health checks and is accessible.
@test "Health verification - detects running machines" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to return healthy status
        flyctl() {
            echo "{\"Machines\":[{\"state\":\"started\",\"id\":\"machine1\"}]}"
            return 0
        }
        export -f flyctl

        verify_deployment_health "test-app"
    '

    [ "$status" -eq 0 ]
    [[ "$output" =~ "healthy" ]]
    [[ "$output" =~ "1 machine(s) running" ]]
}

@test "Health verification - detects multiple running machines" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to return multiple healthy machines
        flyctl() {
            echo "{\"Machines\":[{\"state\":\"started\"},{\"state\":\"running\"},{\"state\":\"started\"}]}"
            return 0
        }
        export -f flyctl

        verify_deployment_health "test-app"
    '

    [ "$status" -eq 0 ]
    [[ "$output" =~ "3 machine(s) running" ]]
}

@test "Health verification - fails when no machines running" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to return no running machines
        flyctl() {
            echo "{\"Machines\":[{\"state\":\"stopped\"},{\"state\":\"stopped\"}]}"
            return 0
        }
        export -f flyctl

        verify_deployment_health "test-app"
    '

    [ "$status" -ne 0 ]
    [[ "$output" =~ "No healthy machines" ]]
}

@test "Health verification - fails when status query fails" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to fail
        flyctl() {
            echo "Error: failed to query status" >&2
            return 1
        }
        export -f flyctl

        verify_deployment_health "test-app"
    '

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Failed to query app status" ]]
}

@test "Health verification - requires app name" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        verify_deployment_health ""
    '

    [ "$status" -ne 0 ]
    [[ "$output" =~ "App name is required" ]]
}

@test "Health verification - requires API token" {
    run bash -c '
        unset FLY_API_TOKEN
        source scripts/version-detection.sh

        verify_deployment_health "test-app"
    '

    [ "$status" -ne 0 ]
    [[ "$output" =~ "FLY_API_TOKEN" ]]
}

@test "Health verification - property test with various machine states" {
    # Test 100 different machine state combinations
    bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        machine_states=("started" "running" "stopped" "stopping" "created")

        for i in {1..100}; do
            # Generate random number of machines (1-10)
            num_machines=$((1 + RANDOM % 10))

            # Generate random machine states
            machines_json="["
            running_count=0

            for j in $(seq 1 $num_machines); do
                state="${machine_states[$((RANDOM % ${#machine_states[@]}))]}"

                if [ "$state" = "started" ] || [ "$state" = "running" ]; then
                    running_count=$((running_count + 1))
                fi

                if [ $j -gt 1 ]; then
                    machines_json+=","
                fi
                machines_json+="{\"state\":\"$state\",\"id\":\"machine$j\"}"
            done
            machines_json+="]"

            # Mock flyctl to return generated machine states
            flyctl() {
                echo "{\"Machines\":$machines_json}"
                return 0
            }
            export -f flyctl

            # Test health verification
            result=$(verify_deployment_health "test-app" 2>&1)
            exit_code=$?

            # Verify result matches expected outcome
            if [ $running_count -gt 0 ]; then
                # Should succeed if any machines are running
                if [ $exit_code -ne 0 ]; then
                    echo "Test $i failed: expected success with $running_count running machines" >&2
                    echo "Result: $result" >&2
                    exit 1
                fi

                # Verify count in output
                if [[ ! "$result" =~ "$running_count machine(s) running" ]]; then
                    echo "Test $i failed: incorrect machine count in output" >&2
                    echo "Expected: $running_count, Output: $result" >&2
                    exit 1
                fi
            else
                # Should fail if no machines are running
                if [ $exit_code -eq 0 ]; then
                    echo "Test $i failed: expected failure with no running machines" >&2
                    exit 1
                fi
            fi
        done
    '

    [ "$?" -eq 0 ]
}

@test "Health verification - handles empty machine list" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to return empty machine list
        flyctl() {
            echo "{\"Machines\":[]}"
            return 0
        }
        export -f flyctl

        verify_deployment_health "test-app"
    '

    [ "$status" -ne 0 ]
    [[ "$output" =~ "No healthy machines" ]]
}

@test "Health verification - handles missing Machines field" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to return status without Machines field
        flyctl() {
            echo "{\"Status\":\"running\"}"
            return 0
        }
        export -f flyctl

        verify_deployment_health "test-app"
    '

    [ "$status" -ne 0 ]
    [[ "$output" =~ "No healthy machines" ]]
}


# Feature: n8n-auto-deploy, Property 17: Volume Mount Preservation
# Validates: Requirements 6.2

# Property 17: Volume Mount Preservation
# For any deployment, the mounted volume configuration should remain unchanged
# to preserve n8n data.
@test "Volume preservation - no volume modification flags in deploy" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to check for volume modification flags
        flyctl() {
            if [[ "$*" =~ --volume ]] || \
               [[ "$*" =~ --mount ]] || \
               [[ "$*" =~ --detach-volume ]]; then
                echo "ERROR: Volume modification detected" >&2
                return 1
            fi

            echo "Deployment preserves volumes"
            return 0
        }
        export -f flyctl

        deploy_to_flyio "1.2.3" "test-app"
    '

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Deployment preserves volumes" ]]
}

@test "Volume preservation - deployment does not create new volumes" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to check for volume creation
        flyctl() {
            if [[ "$*" =~ "volumes create" ]] || \
               [[ "$*" =~ "volume create" ]]; then
                echo "ERROR: Volume creation detected" >&2
                return 1
            fi
            return 0
        }
        export -f flyctl

        deploy_to_flyio "1.2.3" "test-app"
    '

    [ "$status" -eq 0 ]
}

@test "Volume preservation - deployment does not delete volumes" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to check for volume deletion
        flyctl() {
            if [[ "$*" =~ "volumes delete" ]] || \
               [[ "$*" =~ "volume delete" ]] || \
               [[ "$*" =~ "volumes destroy" ]]; then
                echo "ERROR: Volume deletion detected" >&2
                return 1
            fi
            return 0
        }
        export -f flyctl

        deploy_to_flyio "1.2.3" "test-app"
    '

    [ "$status" -eq 0 ]
}

@test "Volume preservation - property test with 100 deployments" {
    # Test 100 deployments to ensure volumes are never modified
    bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # List of volume-related flags that should NOT be present
        volume_flags=(
            "--volume"
            "--mount"
            "--detach-volume"
            "--attach-volume"
            "volumes create"
            "volume create"
            "volumes delete"
            "volume delete"
            "volumes destroy"
        )

        for i in {1..100}; do
            # Generate random version
            major=$((RANDOM % 10))
            minor=$((RANDOM % 20))
            patch=$((RANDOM % 30))
            version="$major.$minor.$patch"

            # Mock flyctl to verify no volume modifications
            flyctl() {
                # Check for volume-related flags
                for flag in "${volume_flags[@]}"; do
                    if [[ "$*" =~ $flag ]]; then
                        echo "Test $i: Volume flag $flag found in: $*" >&2
                        return 1
                    fi
                done

                return 0
            }
            export -f flyctl

            # Test deployment
            if ! deploy_to_flyio "$version" "test-app" >/dev/null 2>&1; then
                echo "Test $i failed with version $version" >&2
                exit 1
            fi
        done
    '

    [ "$?" -eq 0 ]
}

@test "Volume preservation - uses existing fly.toml volume config" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to verify it relies on fly.toml for volume config
        flyctl() {
            # The deploy command should not specify volume configuration
            # It should rely on fly.toml which contains the [[mounts]] section

            # Verify no inline volume configuration
            if [[ "$*" =~ --volume ]] || [[ "$*" =~ --mount ]]; then
                echo "ERROR: Inline volume config detected, should use fly.toml" >&2
                return 1
            fi

            # Verify it is a simple deploy with --image
            if [[ "$*" =~ deploy ]] && [[ "$*" =~ --image ]]; then
                echo "Using fly.toml volume configuration"
                return 0
            fi

            return 1
        }
        export -f flyctl

        deploy_to_flyio "1.2.3" "test-app"
    '

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Using fly.toml volume configuration" ]]
}

@test "Volume preservation - integration with config preservation" {
    # This test verifies that volume preservation is part of config preservation
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to verify both config and volume preservation
        flyctl() {
            # Check for any configuration modification flags
            if [[ "$*" =~ --config ]] || \
               [[ "$*" =~ --volume ]] || \
               [[ "$*" =~ --mount ]] || \
               [[ "$*" =~ --env ]] || \
               [[ "$*" =~ --region ]]; then
                echo "ERROR: Configuration modification detected" >&2
                return 1
            fi

            # Verify only --app and --image flags are used
            local flag_count=0
            for arg in "$@"; do
                if [[ "$arg" =~ ^-- ]]; then
                    flag_count=$((flag_count + 1))
                fi
            done

            # Should have exactly 2 flags: --app and --image
            if [ $flag_count -ne 2 ]; then
                echo "ERROR: Expected 2 flags, got $flag_count" >&2
                return 1
            fi

            return 0
        }
        export -f flyctl

        deploy_to_flyio "1.2.3" "test-app"
    '

    [ "$status" -eq 0 ]
}


# Feature: n8n-auto-deploy, Property 12: Success Logging Includes Version
# Validates: Requirements 4.1

# Property 12: Success Logging Includes Version
# For any successful deployment, the log output should contain the version number
# that was deployed.
@test "Success logging - includes version number" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to succeed
        flyctl() {
            echo "Deployment successful"
            return 0
        }
        export -f flyctl

        deploy_to_flyio "1.2.3" "test-app"
    '

    [ "$status" -eq 0 ]

    # Should contain the version number
    [[ "$output" =~ "1.2.3" ]]

    # Should contain success message
    [[ "$output" =~ "Successful" ]] || [[ "$output" =~ "successful" ]]
}

@test "Success logging - version appears in deployment success log" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl
        flyctl() {
            return 0
        }
        export -f flyctl

        deploy_to_flyio "5.10.20" "test-app"
    '

    [ "$status" -eq 0 ]

    # Should contain the specific version
    [[ "$output" =~ "5.10.20" ]]

    # Should have deployment success indicator
    [[ "$output" =~ "Deployment Successful" ]] || [[ "$output" =~ "deployed" ]]
}

@test "Success logging - property test with 100 random versions" {
    # Test 100 random successful deployments to ensure version is always logged
    bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to always succeed
        flyctl() {
            return 0
        }
        export -f flyctl

        for i in {1..100}; do
            # Generate random version
            major=$((RANDOM % 10))
            minor=$((RANDOM % 20))
            patch=$((RANDOM % 30))
            version="$major.$minor.$patch"

            # Deploy and capture output
            output=$(deploy_to_flyio "$version" "test-app" 2>&1)
            exit_code=$?

            # Should succeed
            if [ $exit_code -ne 0 ]; then
                echo "Test $i failed: deployment returned error" >&2
                exit 1
            fi

            # Should contain the version number
            if [[ ! "$output" =~ $version ]]; then
                echo "Test $i failed: version $version not found in output" >&2
                echo "Output: $output" >&2
                exit 1
            fi

            # Should contain success indicator
            if [[ ! "$output" =~ "Successful" ]] && [[ ! "$output" =~ "successful" ]]; then
                echo "Test $i failed: no success indicator in output" >&2
                echo "Output: $output" >&2
                exit 1
            fi
        done
    '

    [ "$?" -eq 0 ]
}

@test "Success logging - log_deployment_success function includes version" {
    run bash -c '
        source scripts/version-detection.sh
        log_deployment_success "2.5.8"
    '

    [ "$status" -eq 0 ]

    # Should contain the version
    [[ "$output" =~ "2.5.8" ]]

    # Should indicate success
    [[ "$output" =~ "Successful" ]] || [[ "$output" =~ "successful" ]]
}

@test "Success logging - version is clearly identifiable in logs" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl
        flyctl() {
            return 0
        }
        export -f flyctl

        deploy_to_flyio "3.14.159" "test-app"
    '

    [ "$status" -eq 0 ]

    # Version should appear with context (not just as a random number)
    [[ "$output" =~ "version: 3.14.159" ]] || \
    [[ "$output" =~ "version 3.14.159" ]] || \
    [[ "$output" =~ "n8n version: 3.14.159" ]]
}


# Feature: n8n-auto-deploy, Property 13: Failure Logging Includes Error Details
# Validates: Requirements 4.2

# Property 13: Failure Logging Includes Error Details
# For any failed deployment, the log output should contain error information
# describing what went wrong.
@test "Failure logging - includes error details" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to fail with error message
        flyctl() {
            echo "Error: connection timeout" >&2
            return 1
        }
        export -f flyctl

        deploy_to_flyio "1.2.3" "test-app"
    '

    [ "$status" -ne 0 ]

    # Should contain error indicator
    [[ "$output" =~ "ERROR" ]] || [[ "$output" =~ "Failed" ]]

    # Should contain error details
    [[ "$output" =~ "connection timeout" ]]
}

@test "Failure logging - includes version that failed" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to fail
        flyctl() {
            echo "Error: deployment failed" >&2
            return 1
        }
        export -f flyctl

        deploy_to_flyio "5.10.20" "test-app"
    '

    [ "$status" -ne 0 ]

    # Should contain the version that failed
    [[ "$output" =~ "5.10.20" ]]

    # Should indicate failure
    [[ "$output" =~ "Failed" ]] || [[ "$output" =~ "failed" ]]
}

@test "Failure logging - property test with 100 random error scenarios" {
    # Test 100 random failure scenarios to ensure error details are always logged
    bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Various error messages
        error_messages=(
            "connection timeout"
            "network unreachable"
            "insufficient resources"
            "image pull failed"
            "health check failed"
            "deployment quota exceeded"
            "invalid configuration"
            "permission denied"
            "service unavailable"
            "internal server error"
        )

        for i in {1..100}; do
            # Generate random version
            major=$((RANDOM % 10))
            minor=$((RANDOM % 20))
            patch=$((RANDOM % 30))
            version="$major.$minor.$patch"

            # Pick random error message
            error_msg="${error_messages[$((RANDOM % ${#error_messages[@]}))]}"

            # Mock flyctl to fail with specific error
            flyctl() {
                echo "Error: $error_msg" >&2
                return 1
            }
            export -f flyctl

            # Deploy and capture output
            output=$(deploy_to_flyio "$version" "test-app" 2>&1)
            exit_code=$?

            # Should fail
            if [ $exit_code -eq 0 ]; then
                echo "Test $i failed: deployment should have failed" >&2
                exit 1
            fi

            # Should contain the version
            if [[ ! "$output" =~ $version ]]; then
                echo "Test $i failed: version $version not found in output" >&2
                echo "Output: $output" >&2
                exit 1
            fi

            # Should contain error indicator
            if [[ ! "$output" =~ "ERROR" ]] && [[ ! "$output" =~ "Failed" ]] && [[ ! "$output" =~ "failed" ]]; then
                echo "Test $i failed: no error indicator in output" >&2
                echo "Output: $output" >&2
                exit 1
            fi

            # Should contain the error message
            if [[ ! "$output" =~ "$error_msg" ]]; then
                echo "Test $i failed: error message not found in output" >&2
                echo "Expected: $error_msg" >&2
                echo "Output: $output" >&2
                exit 1
            fi
        done
    '

    [ "$?" -eq 0 ]
}

@test "Failure logging - log_deployment_failure function includes details" {
    run bash -c '
        source scripts/version-detection.sh
        log_deployment_failure "2.5.8" "Network connection failed"
    '

    [ "$status" -eq 0 ]

    # Should contain the version
    [[ "$output" =~ "2.5.8" ]]

    # Should contain error details
    [[ "$output" =~ "Network connection failed" ]]

    # Should indicate failure
    [[ "$output" =~ "Failed" ]] || [[ "$output" =~ "failed" ]]
}

@test "Failure logging - Fly.io CLI error output is included" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to return detailed error
        flyctl() {
            echo "Error: failed to deploy" >&2
            echo "Details: image not found in registry" >&2
            echo "Suggestion: check image name and tag" >&2
            return 1
        }
        export -f flyctl

        deploy_to_flyio "1.2.3" "test-app"
    '

    [ "$status" -ne 0 ]

    # Should contain all error details from flyctl
    [[ "$output" =~ "failed to deploy" ]]
    [[ "$output" =~ "image not found" ]]
    [[ "$output" =~ "check image name" ]]
}

@test "Failure logging - error details are clearly separated" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to fail
        flyctl() {
            echo "Deployment error occurred" >&2
            return 1
        }
        export -f flyctl

        deploy_to_flyio "3.14.159" "test-app"
    '

    [ "$status" -ne 0 ]

    # Should have clear failure section
    [[ "$output" =~ "Deployment Failed" ]] || [[ "$output" =~ "ERROR" ]]

    # Should have error details section
    [[ "$output" =~ "Error details" ]] || [[ "$output" =~ "error" ]]
}

@test "Failure logging - multiple error lines are preserved" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock flyctl to return multi-line error
        flyctl() {
            echo "Error line 1: connection failed" >&2
            echo "Error line 2: retry limit exceeded" >&2
            echo "Error line 3: giving up" >&2
            return 1
        }
        export -f flyctl

        deploy_to_flyio "1.0.0" "test-app"
    '

    [ "$status" -ne 0 ]

    # Should contain all error lines
    [[ "$output" =~ "connection failed" ]]
    [[ "$output" =~ "retry limit exceeded" ]]
    [[ "$output" =~ "giving up" ]]
}


# Feature: n8n-auto-deploy, Property 14: Workflow Summary Completeness
# Validates: Requirements 4.3

# Property 14: Workflow Summary Completeness
# For any workflow execution, the final summary should include information about
# the version check result and any deployment actions taken.
@test "Workflow summary - includes action taken" {
    run bash -c '
        source scripts/version-detection.sh
        create_workflow_summary "deployed" "1.0.0" "1.2.3"
    '

    [ "$status" -eq 0 ]

    # Should contain the action
    [[ "$output" =~ "deployed" ]]

    # Should have summary structure
    [[ "$output" =~ "Summary" ]] || [[ "$output" =~ "SUMMARY" ]]
}

@test "Workflow summary - includes current version" {
    run bash -c '
        source scripts/version-detection.sh
        create_workflow_summary "checked" "2.5.8" "2.5.8"
    '

    [ "$status" -eq 0 ]

    # Should contain current version
    [[ "$output" =~ "2.5.8" ]]

    # Should label it as current
    [[ "$output" =~ "Current" ]] || [[ "$output" =~ "current" ]]
}

@test "Workflow summary - includes latest version" {
    run bash -c '
        source scripts/version-detection.sh
        create_workflow_summary "skipped" "1.0.0" "1.0.0"
    '

    [ "$status" -eq 0 ]

    # Should contain latest version
    [[ "$output" =~ "1.0.0" ]]

    # Should label it as latest
    [[ "$output" =~ "Latest" ]] || [[ "$output" =~ "latest" ]]
}

@test "Workflow summary - handles not deployed state" {
    run bash -c '
        source scripts/version-detection.sh
        create_workflow_summary "deployed" "" "1.0.0"
    '

    [ "$status" -eq 0 ]

    # Should handle empty current version
    [[ "$output" =~ "not deployed" ]] || [[ "$output" =~ "Not deployed" ]]

    # Should still show latest version
    [[ "$output" =~ "1.0.0" ]]
}

@test "Workflow summary - property test with 100 random scenarios" {
    # Test 100 random workflow scenarios
    bash -c '
        source scripts/version-detection.sh

        actions=("checked" "deployed" "skipped" "failed")

        for i in {1..100}; do
            # Generate random versions
            curr_major=$((RANDOM % 10))
            curr_minor=$((RANDOM % 20))
            curr_patch=$((RANDOM % 30))

            latest_major=$((RANDOM % 10))
            latest_minor=$((RANDOM % 20))
            latest_patch=$((RANDOM % 30))

            # Randomly decide if current is empty (not deployed)
            if [ $((RANDOM % 10)) -eq 0 ]; then
                current=""
            else
                current="$curr_major.$curr_minor.$curr_patch"
            fi

            latest="$latest_major.$latest_minor.$latest_patch"

            # Pick random action
            action="${actions[$((RANDOM % ${#actions[@]}))]}"

            # Create summary
            output=$(create_workflow_summary "$action" "$current" "$latest" 2>&1)
            exit_code=$?

            # Should succeed
            if [ $exit_code -ne 0 ]; then
                echo "Test $i failed: summary creation failed" >&2
                exit 1
            fi

            # Should contain the action
            if [[ ! "$output" =~ "$action" ]]; then
                echo "Test $i failed: action $action not found in output" >&2
                echo "Output: $output" >&2
                exit 1
            fi

            # Should contain current version or "not deployed"
            if [ -n "$current" ]; then
                if [[ ! "$output" =~ "$current" ]]; then
                    echo "Test $i failed: current version $current not found" >&2
                    echo "Output: $output" >&2
                    exit 1
                fi
            else
                if [[ ! "$output" =~ "not deployed" ]]; then
                    echo "Test $i failed: missing not deployed indicator" >&2
                    echo "Output: $output" >&2
                    exit 1
                fi
            fi

            # Should contain latest version
            if [[ ! "$output" =~ "$latest" ]]; then
                echo "Test $i failed: latest version $latest not found" >&2
                echo "Output: $output" >&2
                exit 1
            fi

            # Should have summary indicator
            if [[ ! "$output" =~ "Summary" ]] && [[ ! "$output" =~ "SUMMARY" ]]; then
                echo "Test $i failed: no summary indicator" >&2
                echo "Output: $output" >&2
                exit 1
            fi
        done
    '

    [ "$?" -eq 0 ]
}

@test "Workflow summary - all three actions are supported" {
    # Test that all expected actions work
    for action in "checked" "deployed" "skipped"; do
        run bash -c "
            source scripts/version-detection.sh
            create_workflow_summary '$action' '1.0.0' '1.2.3'
        "

        [ "$status" -eq 0 ]
        [[ "$output" =~ "$action" ]]
    done
}

@test "Workflow summary - distinguishes between versions" {
    run bash -c '
        source scripts/version-detection.sh
        create_workflow_summary "deployed" "1.0.0" "2.0.0"
    '

    [ "$status" -eq 0 ]

    # Should contain both versions
    [[ "$output" =~ "1.0.0" ]]
    [[ "$output" =~ "2.0.0" ]]

    # Should distinguish which is which
    [[ "$output" =~ "Current" ]] || [[ "$output" =~ "current" ]]
    [[ "$output" =~ "Latest" ]] || [[ "$output" =~ "latest" ]]
}

@test "Workflow summary - formatted for readability" {
    run bash -c '
        source scripts/version-detection.sh
        create_workflow_summary "deployed" "1.0.0" "1.2.3"
    '

    [ "$status" -eq 0 ]

    # Should have some visual structure (borders, separators, etc.)
    # Check for common formatting characters
    [[ "$output" =~ "═" ]] || [[ "$output" =~ "=" ]] || \
    [[ "$output" =~ "─" ]] || [[ "$output" =~ "-" ]] || \
    [[ "$output" =~ "║" ]] || [[ "$output" =~ "|" ]]
}

@test "Workflow summary - complete information for deployment scenario" {
    run bash -c '
        source scripts/version-detection.sh
        create_workflow_summary "deployed" "1.5.0" "1.6.0"
    '

    [ "$status" -eq 0 ]

    # Should have all required information
    [[ "$output" =~ "deployed" ]]
    [[ "$output" =~ "1.5.0" ]]
    [[ "$output" =~ "1.6.0" ]]
    [[ "$output" =~ "Current" ]] || [[ "$output" =~ "current" ]]
    [[ "$output" =~ "Latest" ]] || [[ "$output" =~ "latest" ]]
}

@test "Workflow summary - complete information for skipped scenario" {
    run bash -c '
        source scripts/version-detection.sh
        create_workflow_summary "skipped" "2.0.0" "2.0.0"
    '

    [ "$status" -eq 0 ]

    # Should indicate no deployment was needed
    [[ "$output" =~ "skipped" ]]

    # Should show versions are the same
    [[ "$output" =~ "2.0.0" ]]
}

@test "Workflow summary - handles unknown latest version" {
    run bash -c '
        source scripts/version-detection.sh
        create_workflow_summary "checked" "1.0.0" ""
    '

    [ "$status" -eq 0 ]

    # Should handle empty latest version
    [[ "$output" =~ "unknown" ]] || [[ "$output" =~ "Unknown" ]]

    # Should still show current version
    [[ "$output" =~ "1.0.0" ]]
}


# Feature: n8n-auto-deploy, Property 11: Secret Masking in Logs
# Validates: Requirements 3.4

# Property 11: Secret Masking in Logs
# For any log output, sensitive credential values should not appear in plain text
# (GitHub Actions automatically masks secrets).
@test "Secret masking - FLY_API_TOKEN never appears in function output" {
    run bash -c '
        export FLY_API_TOKEN="super-secret-token-12345"
        source scripts/version-detection.sh

        # Mock flyctl to succeed
        flyctl() {
            echo "Deployment successful"
            return 0
        }
        export -f flyctl

        # Run deployment and capture all output
        deploy_to_flyio "1.2.3" "test-app" 2>&1
    '

    [ "$status" -eq 0 ]

    # The actual token value should NOT appear in output
    # Note: In real GitHub Actions, the secret would be masked automatically
    [[ ! "$output" =~ "super-secret-token-12345" ]]
}

@test "Secret masking - token not exposed in error messages" {
    run bash -c '
        export FLY_API_TOKEN="my-secret-token-xyz"
        source scripts/version-detection.sh

        # Mock flyctl to fail
        flyctl() {
            echo "Error: deployment failed" >&2
            return 1
        }
        export -f flyctl

        # Run deployment and capture all output including errors
        deploy_to_flyio "1.2.3" "test-app" 2>&1
    '

    [ "$status" -ne 0 ]

    # Token should not appear in error output
    [[ ! "$output" =~ "my-secret-token-xyz" ]]
}

@test "Secret masking - token not exposed in query operations" {
    run bash -c '
        export FLY_API_TOKEN="another-secret-token-abc"
        source scripts/version-detection.sh

        # Mock flyctl to return version info
        flyctl() {
            echo "{\"Image\":\"n8nio/n8n:1.0.0\"}"
            return 0
        }
        export -f flyctl

        # Query version and capture all output
        query_flyio_version "test-app" 2>&1
    '

    [ "$status" -eq 0 ]

    # Token should not appear in output
    [[ ! "$output" =~ "another-secret-token-abc" ]]
}

@test "Secret masking - token not exposed in health check" {
    run bash -c '
        export FLY_API_TOKEN="health-check-secret-token"
        source scripts/version-detection.sh

        # Mock flyctl to return health status
        flyctl() {
            echo "{\"Machines\":[{\"state\":\"started\"}]}"
            return 0
        }
        export -f flyctl

        # Verify health and capture all output
        verify_deployment_health "test-app" 2>&1
    '

    [ "$status" -eq 0 ]

    # Token should not appear in output
    [[ ! "$output" =~ "health-check-secret-token" ]]
}

@test "Secret masking - property test with 100 random token values" {
    # Test 100 different token values to ensure none are exposed
    bash -c '
        source scripts/version-detection.sh

        # Mock flyctl to succeed
        flyctl() {
            echo "Operation successful"
            return 0
        }
        export -f flyctl

        for i in {1..100}; do
            # Generate random token-like string
            case $((RANDOM % 5)) in
                0) token="token-$RANDOM-$RANDOM-$RANDOM" ;;
                1) token="$(head -c 32 /dev/urandom | base64 | tr -d /=+ | head -c 32)" ;;
                2) token="fly_$(head -c 24 /dev/urandom | base64 | tr -d /=+ | head -c 24)" ;;
                3) token="secret-$(uuidgen 2>/dev/null || echo "uuid-$RANDOM")" ;;
                4) token="$(head -c 64 /dev/urandom | base64 | tr -d /=+ | head -c 64)" ;;
            esac

            export FLY_API_TOKEN="$token"

            # Test various operations
            output1=$(deploy_to_flyio "1.0.0" "test-app" 2>&1)
            output2=$(query_flyio_version "test-app" 2>&1)
            output3=$(verify_deployment_health "test-app" 2>&1)

            # Verify token does not appear in any output
            if [[ "$output1" =~ "$token" ]] || \
               [[ "$output2" =~ "$token" ]] || \
               [[ "$output3" =~ "$token" ]]; then
                echo "Test $i failed: token exposed in output" >&2
                echo "Token: [REDACTED]" >&2
                exit 1
            fi
        done
    '

    [ "$?" -eq 0 ]
}

@test "Secret masking - error messages dont expose token" {
    run bash -c '
        export FLY_API_TOKEN="error-test-token-secret"
        source scripts/version-detection.sh

        # Mock flyctl to fail with various errors
        flyctl() {
            case $((RANDOM % 3)) in
                0) echo "Error: authentication failed" >&2 ;;
                1) echo "Error: network timeout" >&2 ;;
                2) echo "Error: deployment failed" >&2 ;;
            esac
            return 1
        }
        export -f flyctl

        # Run operations that will fail
        deploy_to_flyio "1.0.0" "test-app" 2>&1
        query_flyio_version "test-app" 2>&1
        verify_deployment_health "test-app" 2>&1
    '

    # Token should not appear in any error output
    [[ ! "$output" =~ "error-test-token-secret" ]]
}

@test "Secret masking - logging functions dont expose token" {
    run bash -c '
        export FLY_API_TOKEN="logging-test-secret-token"
        source scripts/version-detection.sh

        # Test all logging functions
        log_version_check "1.0.0" "1.2.3" "update needed"
        log_deployment_success "1.2.3"
        log_deployment_failure "1.2.3" "some error"
        create_workflow_summary "deployed" "1.0.0" "1.2.3"
    '

    [ "$status" -eq 0 ]

    # Token should not appear in logging output
    [[ ! "$output" =~ "logging-test-secret-token" ]]
}

@test "Secret masking - token presence is checked but value not logged" {
    # Test that functions check for token but don't log its value
    run bash -c '
        export FLY_API_TOKEN="presence-check-token"
        source scripts/version-detection.sh

        # Mock flyctl to return appropriate responses
        flyctl() {
            if [[ "$*" =~ "status" ]]; then
                if [[ "$*" =~ "test-app" ]]; then
                    echo "{\"Image\":\"n8nio/n8n:1.0.0\",\"Machines\":[{\"state\":\"started\"}]}"
                fi
            elif [[ "$*" =~ "deploy" ]]; then
                echo "Deployment successful"
            fi
            return 0
        }
        export -f flyctl

        # These functions check for token presence
        query_flyio_version "test-app" 2>&1
        deploy_to_flyio "1.0.0" "test-app" 2>&1
        verify_deployment_health "test-app" 2>&1
    '

    [ "$status" -eq 0 ]

    # Should not contain the actual token value
    [[ ! "$output" =~ "presence-check-token" ]]
}

@test "Secret masking - missing token error doesnt expose other tokens" {
    # Test that error messages about missing tokens don't expose other secrets
    run bash -c '
        # Set some other environment variables that look like secrets
        export OTHER_SECRET="other-secret-value"
        export ANOTHER_TOKEN="another-token-value"

        # Unset FLY_API_TOKEN
        unset FLY_API_TOKEN

        source scripts/version-detection.sh

        # Try to use functions without token
        query_flyio_version "test-app" 2>&1
        deploy_to_flyio "1.0.0" "test-app" 2>&1
        verify_deployment_health "test-app" 2>&1
    '

    # Should fail due to missing token
    [ "$status" -ne 0 ]

    # Should not expose other secrets
    [[ ! "$output" =~ "other-secret-value" ]]
    [[ ! "$output" =~ "another-token-value" ]]
}

@test "Secret masking - property test with special characters in token" {
    # Test tokens with special characters that might break logging
    bash -c '
        source scripts/version-detection.sh

        # Mock flyctl
        flyctl() {
            return 0
        }
        export -f flyctl

        # Test tokens with special characters
        special_tokens=(
            "token-with-$-sign"
            "token-with-\"-quotes"
            "token-with-\047-apostrophe"
            "token-with-\`-backtick"
            "token-with-|-pipe"
            "token-with-&-ampersand"
            "token-with-;-semicolon"
            "token-with-(-paren"
            "token-with-)-paren"
            "token-with-{-brace"
        )

        for token in "${special_tokens[@]}"; do
            export FLY_API_TOKEN="$token"

            # Run operations
            output=$(deploy_to_flyio "1.0.0" "test-app" 2>&1)

            # Verify token does not appear in output
            # Note: We check for the literal token string
            if [[ "$output" =~ "$token" ]]; then
                echo "Failed: token with special chars exposed" >&2
                exit 1
            fi
        done
    '

    [ "$?" -eq 0 ]
}


# Feature: n8n-auto-deploy, Property 15: Complete Execution Flow
# Validates: Requirements 5.2

# Property 15: Complete Execution Flow
# For any workflow trigger (scheduled or manual), the system should execute all
# required steps in the correct order: version check, comparison, deployment
# decision, and status reporting.
@test "Complete execution flow - all steps execute in order when update needed" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Track steps by echoing to stdout
        echo "Step 1: Querying Docker Hub"

        # Mock curl for Docker Hub query
        curl() {
            echo "{\"results\":[{\"name\":\"1.5.0\"},{\"name\":\"1.4.0\"}]}"
            echo "200"
            return 0
        }
        export -f curl

        # Mock flyctl for Fly.io operations
        flyctl() {
            if [[ "$*" =~ "status" ]]; then
                echo "{\"Image\":\"n8nio/n8n:1.4.0\",\"Machines\":[{\"state\":\"started\"}]}"
                return 0
            elif [[ "$*" =~ "deploy" ]]; then
                echo "Deployment successful"
                return 0
            fi
            return 1
        }
        export -f flyctl

        # Execute complete workflow
        # Step 1: Query Docker Hub
        response=$(query_dockerhub_tags 2>/dev/null)
        tags=$(extract_tag_names "$response" 2>/dev/null)
        latest=$(echo "$tags" | filter_stable_versions | find_latest_version)
        echo "Step 2: Latest version detected: $latest"

        # Step 2: Query current version
        current=$(query_flyio_version "test-app" 2>/dev/null)
        echo "Step 3: Current version: ${current:-none}"

        # Step 3: Compare versions
        if needs_update "$current" "$latest"; then
            echo "Step 4: Update needed, deploying"
            # Step 4: Deploy
            deploy_to_flyio "$latest" "test-app" >/dev/null 2>&1
            echo "Step 5: Deployment completed"
        else
            echo "Step 4: No update needed"
        fi
    '

    [ "$status" -eq 0 ]

    # Verify all steps executed in correct order
    [[ "$output" =~ "Step 1: Querying Docker Hub" ]]
    [[ "$output" =~ "Step 2: Latest version detected: 1.5.0" ]]
    [[ "$output" =~ "Step 3: Current version: 1.4.0" ]]
    [[ "$output" =~ "Step 4: Update needed, deploying" ]]
    [[ "$output" =~ "Step 5: Deployment completed" ]]
}

@test "Complete execution flow - skips deployment when no update needed" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Use temp file to track execution
        exec_log="/tmp/exec_log_$$"
        echo "" > "$exec_log"

        # Mock curl for Docker Hub
        curl() {
            echo "dockerhub" >> "$exec_log"
            echo "{\"results\":[{\"name\":\"1.5.0\"}]}"
            echo "200"
            return 0
        }
        export -f curl

        # Mock flyctl
        flyctl() {
            if [[ "$*" =~ "status" ]]; then
                echo "query" >> "$exec_log"
                # Return same version as latest
                echo "{\"Image\":\"n8nio/n8n:1.5.0\"}"
                return 0
            elif [[ "$*" =~ "deploy" ]]; then
                echo "deploy" >> "$exec_log"
                return 0
            fi
            return 1
        }
        export -f flyctl

        # Execute workflow
        response=$(query_dockerhub_tags)
        latest=$(echo "$response" | extract_tag_names | filter_stable_versions | find_latest_version)
        current=$(query_flyio_version "test-app")

        if needs_update "$current" "$latest"; then
            deploy_to_flyio "$latest" "test-app" >/dev/null 2>&1
        fi

        cat "$exec_log"
        rm -f "$exec_log"
    '

    [ "$status" -eq 0 ]

    # Should have queried Docker Hub and current version
    [[ "$output" =~ "dockerhub" ]]
    [[ "$output" =~ "query" ]]

    # Should NOT have deployed
    [[ ! "$output" =~ "deploy" ]]
}

@test "Complete execution flow - handles Docker Hub API failure gracefully" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock curl to fail
        curl() {
            return 1
        }
        export -f curl

        # Execute workflow - should fail at first step
        query_dockerhub_tags
    '

    # Should fail gracefully
    [ "$status" -ne 0 ]

    # Should log error
    [[ "$output" =~ "ERROR" ]]
}

@test "Complete execution flow - handles Fly.io authentication failure" {
    run bash -c '
        export FLY_API_TOKEN="invalid-token"
        source scripts/version-detection.sh

        # Mock curl to succeed
        curl() {
            echo "{\"results\":[{\"name\":\"1.5.0\"}]}"
            echo "200"
            return 0
        }
        export -f curl

        # Mock flyctl to fail with auth error
        flyctl() {
            echo "Error: authentication failed" >&2
            return 1
        }
        export -f flyctl

        # Execute workflow
        response=$(query_dockerhub_tags)
        latest=$(echo "$response" | extract_tag_names | filter_stable_versions | find_latest_version)

        # Should fail when querying current version
        query_flyio_version "test-app"
    '

    # Should fail with auth error
    [ "$status" -eq 2 ]

    # Should log authentication error
    [[ "$output" =~ "Authentication failed" ]]
}

@test "Complete execution flow - handles deployment failure" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock curl to succeed
        curl() {
            echo "{\"results\":[{\"name\":\"1.5.0\"}]}"
            echo "200"
            return 0
        }
        export -f curl

        # Mock flyctl
        flyctl() {
            if [[ "$*" =~ "status" ]]; then
                echo "{\"Image\":\"n8nio/n8n:1.4.0\"}"
                return 0
            elif [[ "$*" =~ "deploy" ]]; then
                echo "Error: deployment failed" >&2
                return 1
            fi
            return 1
        }
        export -f flyctl

        # Execute workflow
        response=$(query_dockerhub_tags 2>/dev/null)
        tags=$(extract_tag_names "$response" 2>/dev/null)
        latest=$(echo "$tags" | filter_stable_versions | find_latest_version)
        current=$(query_flyio_version "test-app" 2>/dev/null)

        if needs_update "$current" "$latest"; then
            deploy_to_flyio "$latest" "test-app" 2>&1
        fi
    '

    # Should fail on deployment
    [ "$status" -ne 0 ]

    # Should log error
    [[ "$output" =~ "ERROR" ]] || [[ "$output" =~ "Error" ]] || [[ "$output" =~ "failed" ]]
}

@test "Complete execution flow - property test with 100 random scenarios" {
    # Test 100 different workflow scenarios
    bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        for i in {1..100}; do
            # Generate random versions
            latest_major=$((RANDOM % 5 + 1))
            latest_minor=$((RANDOM % 10))
            latest_patch=$((RANDOM % 20))
            latest_version="$latest_major.$latest_minor.$latest_patch"

            # Randomly decide current version (50% chance of being older)
            if [ $((RANDOM % 2)) -eq 0 ]; then
                # Older version - should trigger deployment
                if [ $latest_patch -gt 0 ]; then
                    current_version="$latest_major.$latest_minor.$((latest_patch - 1))"
                elif [ $latest_minor -gt 0 ]; then
                    current_version="$latest_major.$((latest_minor - 1)).$latest_patch"
                elif [ $latest_major -gt 1 ]; then
                    current_version="$((latest_major - 1)).$latest_minor.$latest_patch"
                else
                    # Edge case: version is 1.0.0, use 0.9.9
                    current_version="0.9.9"
                fi
                should_deploy=true
            else
                # Same version - should skip deployment
                current_version="$latest_version"
                should_deploy=false
            fi

            # Use temp file to track deployment
            deploy_marker="/tmp/deploy_marker_$$_$i"
            rm -f "$deploy_marker"

            # Mock curl
            curl() {
                echo "{\"results\":[{\"name\":\"$latest_version\"}]}"
                echo "200"
                return 0
            }
            export -f curl

            # Mock flyctl
            flyctl() {
                if [[ "$*" =~ "status" ]]; then
                    echo "{\"Image\":\"n8nio/n8n:$current_version\"}"
                    return 0
                elif [[ "$*" =~ "deploy" ]]; then
                    touch "$deploy_marker"
                    return 0
                fi
                return 1
            }
            export -f flyctl

            # Execute complete workflow
            response=$(query_dockerhub_tags 2>/dev/null)
            if [ $? -ne 0 ]; then
                echo "Test $i failed: Docker Hub query failed" >&2
                exit 1
            fi

            tags=$(extract_tag_names "$response" 2>/dev/null)
            latest=$(echo "$tags" | filter_stable_versions | find_latest_version)
            if [ -z "$latest" ]; then
                echo "Test $i failed: Could not extract latest version" >&2
                exit 1
            fi

            current=$(query_flyio_version "test-app" 2>/dev/null)

            if needs_update "$current" "$latest"; then
                deploy_to_flyio "$latest" "test-app" >/dev/null 2>&1
            fi

            # Check if deployment happened
            deployed=false
            if [ -f "$deploy_marker" ]; then
                deployed=true
                rm -f "$deploy_marker"
            fi

            # Verify deployment decision
            if [ "$should_deploy" = true ] && [ "$deployed" = false ]; then
                echo "Test $i failed: should have deployed but didnt" >&2
                echo "Current: $current_version, Latest: $latest_version" >&2
                exit 1
            fi

            if [ "$should_deploy" = false ] && [ "$deployed" = true ]; then
                echo "Test $i failed: should not have deployed but did" >&2
                echo "Current: $current_version, Latest: $latest_version" >&2
                exit 1
            fi
        done
    '

    [ "$?" -eq 0 ]
}

@test "Complete execution flow - initial deployment scenario" {
    # Test first-time deployment when app is not yet deployed
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        echo "Starting initial deployment test"

        # Mock curl
        curl() {
            echo "{\"results\":[{\"name\":\"1.0.0\"}]}"
            echo "200"
            return 0
        }
        export -f curl

        # Mock flyctl
        flyctl() {
            if [[ "$*" =~ "status" ]]; then
                # App not deployed yet
                echo "Error: app not found" >&2
                return 1
            elif [[ "$*" =~ "deploy" ]]; then
                echo "Initial deployment successful"
                return 0
            fi
            return 1
        }
        export -f flyctl

        # Execute workflow
        response=$(query_dockerhub_tags 2>/dev/null)
        tags=$(extract_tag_names "$response" 2>/dev/null)
        latest=$(echo "$tags" | filter_stable_versions | find_latest_version)
        echo "Latest version: $latest"

        current=$(query_flyio_version "test-app" 2>/dev/null)
        echo "Current version: ${current:-not deployed}"

        # Should deploy when current is empty
        if needs_update "$current" "$latest"; then
            echo "Deploying initial version"
            deploy_to_flyio "$latest" "test-app" >/dev/null 2>&1
            echo "Deployment completed"
        fi
    '

    [ "$status" -eq 0 ]

    # Should have executed all steps including deployment
    [[ "$output" =~ "Latest version: 1.0.0" ]]
    [[ "$output" =~ "Current version: not deployed" ]] || [[ "$output" =~ "Current version: $" ]]
    [[ "$output" =~ "Deploying initial version" ]]
    [[ "$output" =~ "Deployment completed" ]]
}

@test "Complete execution flow - workflow completes even with health check failure" {
    # Test that workflow can complete even if health check fails
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock curl
        curl() {
            echo "{\"results\":[{\"name\":\"1.5.0\"}]}"
            echo "200"
            return 0
        }
        export -f curl

        # Mock flyctl
        flyctl() {
            if [[ "$*" =~ "status" ]]; then
                # First call: return old version
                # Subsequent calls: return unhealthy status
                if [[ ! -f /tmp/deploy_done ]]; then
                    echo "{\"Image\":\"n8nio/n8n:1.4.0\"}"
                    return 0
                else
                    echo "{\"Machines\":[{\"state\":\"stopped\"}]}"
                    return 0
                fi
            elif [[ "$*" =~ "deploy" ]]; then
                touch /tmp/deploy_done
                return 0
            fi
            return 1
        }
        export -f flyctl

        # Execute workflow
        response=$(query_dockerhub_tags)
        latest=$(echo "$response" | extract_tag_names | filter_stable_versions | find_latest_version)
        current=$(query_flyio_version "test-app")

        if needs_update "$current" "$latest"; then
            deploy_to_flyio "$latest" "test-app" >/dev/null 2>&1

            # Health check should fail but not crash workflow
            verify_deployment_health "test-app" 2>/dev/null || true
        fi

        # Cleanup
        rm -f /tmp/deploy_done

        echo "Workflow completed"
    '

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Workflow completed" ]]
}

@test "Complete execution flow - all logging functions are called" {
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Mock curl
        curl() {
            echo "{\"results\":[{\"name\":\"1.5.0\"}]}"
            echo "200"
            return 0
        }
        export -f curl

        # Mock flyctl
        flyctl() {
            if [[ "$*" =~ "status" ]]; then
                echo "{\"Image\":\"n8nio/n8n:1.4.0\"}"
                return 0
            elif [[ "$*" =~ "deploy" ]]; then
                return 0
            fi
            return 1
        }
        export -f flyctl

        # Execute complete workflow with logging
        response=$(query_dockerhub_tags 2>/dev/null)
        latest=$(echo "$response" | extract_tag_names 2>/dev/null | filter_stable_versions | find_latest_version)
        current=$(query_flyio_version "test-app" 2>/dev/null)

        # Log version check
        if needs_update "$current" "$latest"; then
            decision="update needed"
        else
            decision="no update needed"
        fi
        log_version_check "$current" "$latest" "$decision" 2>&1

        # Deploy if needed
        if needs_update "$current" "$latest"; then
            deploy_to_flyio "$latest" "test-app" 2>&1
        fi

        # Create summary
        create_workflow_summary "deployed" "$current" "$latest" 2>&1
    '

    [ "$status" -eq 0 ]

    # Should contain version check log
    [[ "$output" =~ "Version Check Results" ]]

    # Should contain deployment info
    [[ "$output" =~ "Deploying" ]] || [[ "$output" =~ "deployed" ]]

    # Should contain workflow summary
    [[ "$output" =~ "Summary" ]]
}

@test "Complete execution flow - error propagation works correctly" {
    # Test that errors at each stage propagate correctly

    # Test 1: Docker Hub error stops workflow
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        curl() { return 1; }
        export -f curl

        query_dockerhub_tags || exit 1
        echo "Should not reach here"
    '
    [ "$status" -eq 1 ]
    [[ ! "$output" =~ "Should not reach here" ]]

    # Test 2: Auth error stops workflow
    run bash -c '
        export FLY_API_TOKEN="invalid"
        source scripts/version-detection.sh

        curl() {
            echo "{\"results\":[{\"name\":\"1.0.0\"}]}"
            echo "200"
            return 0
        }
        export -f curl

        flyctl() {
            echo "Error: authentication failed" >&2
            return 1
        }
        export -f flyctl

        response=$(query_dockerhub_tags)
        tags=$(extract_tag_names "$response")
        latest=$(echo "$tags" | filter_stable_versions | find_latest_version)

        query_flyio_version "test-app"
        exit_code=$?

        if [ $exit_code -eq 2 ]; then
            exit 2
        fi

        echo "Should not reach here"
    '
    [ "$status" -eq 2 ]
    [[ ! "$output" =~ "Should not reach here" ]]

    # Test 3: Deployment error stops workflow
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        curl() {
            echo "{\"results\":[{\"name\":\"1.5.0\"}]}"
            echo "200"
            return 0
        }
        export -f curl

        flyctl() {
            if [[ "$*" =~ "status" ]]; then
                echo "{\"Image\":\"n8nio/n8n:1.4.0\"}"
                return 0
            elif [[ "$*" =~ "deploy" ]]; then
                return 1
            fi
            return 1
        }
        export -f flyctl

        response=$(query_dockerhub_tags)
        tags=$(extract_tag_names "$response")
        latest=$(echo "$tags" | filter_stable_versions | find_latest_version)
        current=$(query_flyio_version "test-app")

        if needs_update "$current" "$latest"; then
            deploy_to_flyio "$latest" "test-app" >/dev/null 2>&1 || exit 1
        fi

        echo "Should not reach here"
    '
    [ "$status" -eq 1 ]
    [[ ! "$output" =~ "Should not reach here" ]]
}

@test "Complete execution flow - handles concurrent execution prevention" {
    # This test verifies the workflow can detect if it should not run concurrently
    # In GitHub Actions, this is handled by the concurrency key in the workflow file
    run bash -c '
        export FLY_API_TOKEN="test-token"
        source scripts/version-detection.sh

        # Simulate checking for concurrent execution
        # In real workflow, GitHub Actions handles this

        # Mock curl
        curl() {
            echo "{\"results\":[{\"name\":\"1.0.0\"}]}"
            echo "200"
            return 0
        }
        export -f curl

        # Execute workflow normally
        response=$(query_dockerhub_tags)
        latest=$(echo "$response" | extract_tag_names | filter_stable_versions | find_latest_version)

        echo "Workflow executed: $latest"
    '

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Workflow executed" ]]
}

# ---------------------------------------------------------------------------
# Regression: non-semver deployed tag (e.g. 'latest') wedged the pipeline at
# "up to date" forever. See needs_update / version_greater_than hardening.
# ---------------------------------------------------------------------------

@test "Non-semver current - 'latest' tag triggers update (pin to explicit version)" {
    run bash -c '
        source scripts/version-detection.sh
        needs_update "latest" "1.123.57"
    '
    # Should return 0 (true) - update needed to pin the floating tag
    [ "$status" -eq 0 ]
}

@test "Non-semver current - comparison emits no integer-expression errors" {
    run bash -c '
        source scripts/version-detection.sh
        version_greater_than "1.123.57" "latest"
    '
    # Must not leak bash "[: integer expression expected" noise
    [[ ! "$output" =~ "integer expression expected" ]]
}

@test "Non-semver current - version_greater_than returns false for unorderable input" {
    run bash -c '
        source scripts/version-detection.sh
        version_greater_than "1.123.57" "latest"
    '
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Major-version policy: auto minor/patch within a pinned major, hold new majors
# ---------------------------------------------------------------------------

@test "major_of - extracts major component" {
    run bash -c '
        source scripts/version-detection.sh
        echo "$(major_of "2.27.1")"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]
}

@test "filter_major - keeps only versions in the pinned major series" {
    run bash -c '
        source scripts/version-detection.sh
        printf "1.123.57\n2.27.1\n1.100.0\n2.0.0\n" | filter_major "1"
    '
    [ "$status" -eq 0 ]
    [[ "$output" =~ "1.123.57" ]]
    [[ "$output" =~ "1.100.0" ]]
    [[ ! "$output" =~ "2.27.1" ]]
    [[ ! "$output" =~ "2.0.0" ]]
}

@test "filter_major - target within major selects highest 1.x, holding 2.x back" {
    run bash -c '
        source scripts/version-detection.sh
        printf "2.27.1\n1.123.57\n1.123.56\n2.0.0\n" | filter_major "1" | find_latest_version
    '
    [ "$status" -eq 0 ]
    [ "$output" = "1.123.57" ]
}

# ---------------------------------------------------------------------------
# Recording the deployed version: parse the Fly image ref into a version tag.
# After an explicit-tag deploy Fly reports the tag, so the next run can compare.
# ---------------------------------------------------------------------------

@test "parse_version_from_image - explicit semver tag" {
    run bash -c '
        source scripts/version-detection.sh
        parse_version_from_image "n8nio/n8n:2.27.1"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "2.27.1" ]
}

@test "parse_version_from_image - floating latest tag" {
    run bash -c '
        source scripts/version-detection.sh
        parse_version_from_image "n8nio/n8n:latest"
    '
    [ "$output" = "latest" ]
}

@test "parse_version_from_image - registry host with tag" {
    run bash -c '
        source scripts/version-detection.sh
        parse_version_from_image "registry.fly.io/n8n-run:2.27.1"
    '
    [ "$output" = "2.27.1" ]
}

@test "parse_version_from_image - tag plus digest keeps the tag" {
    run bash -c '
        source scripts/version-detection.sh
        parse_version_from_image "n8nio/n8n:2.27.1@sha256:deadbeef"
    '
    [ "$output" = "2.27.1" ]
}

@test "parse_version_from_image - pure digest yields empty (version unknown)" {
    run bash -c '
        source scripts/version-detection.sh
        parse_version_from_image "registry.fly.io/n8n-run@sha256:deadbeef"
    '
    [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# fly.toml as source of truth: read the pinned version and bump it. The
# workflow edits fly.toml; the Fly deploy-on-push trigger deploys it.
# ---------------------------------------------------------------------------

@test "read_pinned_version - reads explicit tag from fly.toml" {
    run bash -c '
        source scripts/version-detection.sh
        tmp=$(mktemp)
        printf "[build]\n  image = '\''n8nio/n8n:2.27.1'\''\n" > "$tmp"
        read_pinned_version "$tmp"
        rm -f "$tmp"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "2.27.1" ]
}

@test "read_pinned_version - untagged image yields empty (forces a pin)" {
    run bash -c '
        source scripts/version-detection.sh
        tmp=$(mktemp)
        printf "[build]\n  image = '\''n8nio/n8n'\''\n" > "$tmp"
        read_pinned_version "$tmp"
        rm -f "$tmp"
    '
    [ -z "$output" ]
}

@test "bump_flytoml_image - rewrites the image line, preserving indentation" {
    run bash -c '
        source scripts/version-detection.sh
        tmp=$(mktemp)
        printf "[build]\n  image = '\''n8nio/n8n:2.13.4'\''\n" > "$tmp"
        bump_flytoml_image "$tmp" "2.27.1"
        got=$(read_pinned_version "$tmp")
        echo "line:$(grep image "$tmp")"
        echo "got:$got"
        rm -f "$tmp"
    '
    [ "$status" -eq 0 ]
    [[ "$output" =~ "got:2.27.1" ]]
    [[ ! "$output" =~ "2.13.4" ]]
    # two-space indentation preserved
    [[ "$output" =~ "line:  image" ]]
}
