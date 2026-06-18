#!/usr/bin/env bats
#
# Fly.io access: query/deploy/health and FLY_API_TOKEN handling.
# See scripts/lib/flyio.sh.

setup() {
    load 'test_helper'
}

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

