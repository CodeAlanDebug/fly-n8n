#!/usr/bin/env bats
#
# Docker Hub access (query_dockerhub_tags). See scripts/lib/dockerhub.sh.

setup() {
    load 'test_helper'
}

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

