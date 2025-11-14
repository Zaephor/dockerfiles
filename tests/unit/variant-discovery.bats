#!/usr/bin/env bats
# Tests for variant discovery library
#
# Tests cover discovery of multiple variants, default variant handling,
# invalid variant name rejection, and edge cases.

# Setup: Source the variant discovery library
setup() {
    # Find the project root (BATS_TEST_DIRNAME is tests/unit, go up two levels)
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../" && pwd)"

    # Source the variant discovery library
    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/.github/scripts/lib/variant-discovery.sh"

    # Create temporary test directory
    TEST_DIR="$(mktemp -d)"
}

# Teardown: Clean up temporary test directory
teardown() {
    if [[ -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

#######################################
# Test: Discover multiple variants
#######################################
@test "discover_variants discovers default and named variants" {
    # Create test Dockerfiles
    touch "${TEST_DIR}/Dockerfile"
    touch "${TEST_DIR}/Dockerfile.alpine"
    touch "${TEST_DIR}/Dockerfile.slim"

    # Run discovery
    output=$(discover_variants --image-dir "$TEST_DIR")

    # Verify JSON structure
    [[ "$output" =~ "variants" ]]

    # Verify all variants are present
    [[ "$output" =~ "default" ]]
    [[ "$output" =~ "alpine" ]]
    [[ "$output" =~ "slim" ]]
}

#######################################
# Test: Default variant always present
#######################################
@test "discover_variants always includes default variant" {
    # Create only default Dockerfile
    touch "${TEST_DIR}/Dockerfile"

    # Run discovery
    output=$(discover_variants --image-dir "$TEST_DIR")

    # Verify default variant is present
    [[ "$output" =~ "default" ]]
    [[ "$output" =~ "Dockerfile" ]]
}

#######################################
# Test: Invalid variant names rejected
#######################################
@test "discover_variants skips variants with invalid names" {
    # Create valid Dockerfiles
    touch "${TEST_DIR}/Dockerfile"
    touch "${TEST_DIR}/Dockerfile.validname"

    # Create invalid Dockerfiles (uppercase, special chars)
    touch "${TEST_DIR}/Dockerfile.InvalidName"
    touch "${TEST_DIR}/Dockerfile.invalid_name"

    # Run discovery
    output=$(discover_variants --image-dir "$TEST_DIR")

    # Verify only valid variants included
    [[ "$output" =~ "validname" ]]
    [[ ! "$output" =~ "InvalidName" ]]
    [[ ! "$output" =~ "invalid_name" ]]
}

#######################################
# Test: Template files excluded
#######################################
@test "discover_variants excludes Dockerfile.template" {
    # Create Dockerfiles
    touch "${TEST_DIR}/Dockerfile"
    touch "${TEST_DIR}/Dockerfile.alpine"
    touch "${TEST_DIR}/Dockerfile.template"

    # Run discovery
    output=$(discover_variants --image-dir "$TEST_DIR")

    # Template should not be in output
    [[ ! "$output" =~ "template" ]]

    # Alpine should be in output
    [[ "$output" =~ "alpine" ]]
}

#######################################
# Test: Directory not found error
#######################################
@test "discover_variants returns error when directory not found" {
    # Try to discover in non-existent directory
    run discover_variants --image-dir "/nonexistent/path"

    # Should fail with exit code 1
    [[ $status -eq 1 ]]
}

#######################################
# Test: No Dockerfile error
#######################################
@test "discover_variants returns error when no Dockerfile found" {
    # Create directory without Dockerfile
    mkdir -p "${TEST_DIR}/empty"

    # Try to discover
    run discover_variants --image-dir "${TEST_DIR}/empty"

    # Should fail with exit code 2
    [[ $status -eq 2 ]]
}

#######################################
# Test: Missing required argument
#######################################
@test "discover_variants returns error when --image-dir missing" {
    # Try to discover without argument
    run discover_variants

    # Should fail
    [[ $status -eq 1 ]]
}

#######################################
# Test: validate_variant_name accepts valid names
#######################################
@test "validate_variant_name accepts lowercase alphanumeric with hyphens" {
    # Valid names
    validate_variant_name "alpine"
    [[ $? -eq 0 ]]

    validate_variant_name "arm64base"
    [[ $? -eq 0 ]]

    validate_variant_name "slimpy3"
    [[ $? -eq 0 ]]
}

#######################################
# Test: validate_variant_name rejects invalid names
#######################################
@test "validate_variant_name rejects uppercase and underscores" {
    # Invalid names should fail
    run validate_variant_name "Alpine"
    [[ $status -eq 1 ]]

    run validate_variant_name "alpine_slim"
    [[ $status -eq 1 ]]
}

#######################################
# Test: validate_variant_name rejects "default"
#######################################
@test "validate_variant_name rejects default (reserved)" {
    run validate_variant_name "default"
    [[ $status -eq 1 ]]
}

#######################################
# Test: validate_variant_name rejects empty string
#######################################
@test "validate_variant_name rejects empty string" {
    run validate_variant_name ""
    [[ $status -eq 1 ]]
}

#######################################
# Test: validate_variant_name rejects consecutive hyphens
#######################################
@test "validate_variant_name rejects consecutive hyphens" {
    # Reject names with consecutive hyphens
    run validate_variant_name "alpine--slim"
    [[ $status -eq 1 ]]

    run validate_variant_name "test---variant"
    [[ $status -eq 1 ]]

    # Accept valid hyphenated names
    run validate_variant_name "alpine-slim"
    [[ $status -eq 0 ]]
}

#######################################
# Test: get_dockerfile_path returns default variant path
#######################################
@test "get_dockerfile_path returns Dockerfile for default variant" {
    # Create Dockerfile
    touch "${TEST_DIR}/Dockerfile"

    # Get path
    output=$(get_dockerfile_path "$TEST_DIR" "default")

    [[ "$output" == "${TEST_DIR}/Dockerfile" ]]
}

#######################################
# Test: get_dockerfile_path returns variant-specific path
#######################################
@test "get_dockerfile_path returns Dockerfile.variant for named variant" {
    # Create Dockerfile.alpine
    touch "${TEST_DIR}/Dockerfile.alpine"

    # Get path
    output=$(get_dockerfile_path "$TEST_DIR" "alpine")

    [[ "$output" == "${TEST_DIR}/Dockerfile.alpine" ]]
}

#######################################
# Test: get_dockerfile_path fails when file not found
#######################################
@test "get_dockerfile_path returns error when Dockerfile not found" {
    # Try to get path for non-existent variant
    run get_dockerfile_path "$TEST_DIR" "nonexistent"

    # Should fail
    [[ $status -eq 1 ]]
}

#######################################
# Test: get_dockerfile_path requires both arguments
#######################################
@test "get_dockerfile_path requires both image_dir and variant arguments" {
    # Try without variant
    run get_dockerfile_path "$TEST_DIR"

    # Should fail
    [[ $status -eq 1 ]]
}
