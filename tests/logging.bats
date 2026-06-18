#!/usr/bin/env bats
#
# Logging and run-summary helpers. See scripts/lib/logging.sh.

setup() {
    load 'test_helper'
}

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

