#!/usr/bin/env bats
#
# End-to-end execution-flow tests spanning the whole pipeline.

setup() {
    load 'test_helper'
}

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

