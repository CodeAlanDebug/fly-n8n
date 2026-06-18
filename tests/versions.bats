#!/usr/bin/env bats
#
# Version logic: filtering, comparison, semver, the deploy decision,
# and fly.toml read/write. See scripts/lib/versions.sh.

setup() {
    load 'test_helper'
}

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

@test "resolve_latest_version - maps :latest digest to its version tag" {
    run bash -c '
        source scripts/version-detection.sh
        json='"'"'{"results":[
          {"name":"latest","digest":"sha256:AAA"},
          {"name":"2.26.6","digest":"sha256:AAA"},
          {"name":"2.26","digest":"sha256:AAA"},
          {"name":"2.27.1","digest":"sha256:BBB"},
          {"name":"next","digest":"sha256:CCC"}
        ]}'"'"'
        resolve_latest_version "$json"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "2.26.6" ]
}

@test "resolve_latest_version - no latest tag yields empty" {
    run bash -c '
        source scripts/version-detection.sh
        json='"'"'{"results":[{"name":"2.27.1","digest":"sha256:BBB"}]}'"'"'
        resolve_latest_version "$json"
    '
    [ -z "$output" ]
}

@test "resolve_latest_version - picks highest semver when several share the digest" {
    run bash -c '
        source scripts/version-detection.sh
        json='"'"'{"results":[
          {"name":"latest","digest":"sha256:AAA"},
          {"name":"2.26.5","digest":"sha256:AAA"},
          {"name":"2.26.6","digest":"sha256:AAA"}
        ]}'"'"'
        resolve_latest_version "$json"
    '
    [ "$output" = "2.26.6" ]
}

