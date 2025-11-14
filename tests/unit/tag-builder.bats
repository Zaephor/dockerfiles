#!/usr/bin/env bats
# Tests for tag builder library
#
# Tests cover variant tag generation, default variant handling,
# architecture-specific tags, and multi-registry tag generation.

# Setup: Source the tag builder library
setup() {
    # Find the project root (BATS_TEST_DIRNAME is tests/unit, go up two levels)
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../" && pwd)"

    # Source the tag builder library
    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/.github/scripts/lib/tag-builder.sh"
}

#######################################
# Test: Default variant omits suffix
#######################################
@test "build_variant_tags generates correct tags for default variant" {
    output=$(build_variant_tags --image hello-world --version 1.0.0 --variant default --registry ghcr.io/user/repo)

    # Should include version-only tag for default variant
    [[ "$output" =~ "ghcr.io/user/repo/hello-world:1.0.0" ]]

    # Should include latest for default variant
    [[ "$output" =~ "ghcr.io/user/repo/hello-world:latest" ]]

    # Should NOT include variant suffix
    [[ ! "$output" =~ "default" ]]
}

#######################################
# Test: Named variant includes suffix
#######################################
@test "build_variant_tags includes variant suffix for named variants" {
    output=$(build_variant_tags --image hello-world --version 1.0.0 --variant alpine --registry ghcr.io/user/repo)

    # Should include version-variant tag
    [[ "$output" =~ "ghcr.io/user/repo/hello-world:1.0.0-alpine" ]]

    # Should include variant-only tag
    [[ "$output" =~ "ghcr.io/user/repo/hello-world:alpine" ]]

    # Should include latest-variant tag
    [[ "$output" =~ "ghcr.io/user/repo/hello-world:latest-alpine" ]]
}

#######################################
# Test: Architecture-specific tags
#######################################
@test "build_variant_tags generates architecture-specific tags" {
    output=$(build_variant_tags --image hello-world --version 1.0.0 --variant alpine --arch amd64 --registry ghcr.io/user/repo)

    # Should include version-variant-arch tag
    [[ "$output" =~ "ghcr.io/user/repo/hello-world:1.0.0-alpine-amd64" ]]
}

#######################################
# Test: Default variant architecture-specific tags
#######################################
@test "build_variant_tags generates architecture tags for default variant" {
    output=$(build_variant_tags --image hello-world --version 1.0.0 --variant default --arch amd64 --registry ghcr.io/user/repo)

    # Should include version-arch tag (no variant suffix for default)
    [[ "$output" =~ "ghcr.io/user/repo/hello-world:1.0.0-amd64" ]]

    # Should NOT include "default" variant name
    [[ ! "$output" =~ "default" ]]
}

#######################################
# Test: arm64 architecture
#######################################
@test "build_variant_tags works with arm64 architecture" {
    output=$(build_variant_tags --image hello-world --version 1.0.0 --variant alpine --arch arm64 --registry ghcr.io/user/repo)

    # Should include arm64-specific tag
    [[ "$output" =~ "ghcr.io/user/repo/hello-world:1.0.0-alpine-arm64" ]]
}

#######################################
# Test: Missing required arguments
#######################################
@test "build_variant_tags requires --image argument" {
    run build_variant_tags --version 1.0.0 --variant alpine

    [[ $status -eq 1 ]]
}

@test "build_variant_tags requires --version argument" {
    run build_variant_tags --image hello-world --variant alpine

    [[ $status -eq 1 ]]
}

@test "build_variant_tags requires --variant argument" {
    run build_variant_tags --image hello-world --version 1.0.0

    [[ $status -eq 1 ]]
}

#######################################
# Test: Whitespace-only version rejection
#######################################
@test "build_variant_tags rejects whitespace-only version" {
    run build_variant_tags --image hello-world --version "   " --variant alpine

    [[ $status -eq 1 ]]
}

#######################################
# Test: Invalid architecture
#######################################
@test "build_variant_tags rejects invalid architecture" {
    run build_variant_tags --image hello-world --version 1.0.0 --variant alpine --arch invalid

    [[ $status -eq 1 ]]
}

#######################################
# Test: Multiple variants tag generation
#######################################
@test "build_variant_tags works for slim variant" {
    output=$(build_variant_tags --image hello-world --version 1.0.0 --variant slim --registry ghcr.io/user/repo)

    [[ "$output" =~ "ghcr.io/user/repo/hello-world:1.0.0-slim" ]]
    [[ "$output" =~ "ghcr.io/user/repo/hello-world:slim" ]]
    [[ "$output" =~ "ghcr.io/user/repo/hello-world:latest-slim" ]]
}

#######################################
# Test: Default registry prefix
#######################################
@test "build_variant_tags uses default registry if not provided" {
    output=$(build_variant_tags --image hello-world --version 1.0.0 --variant alpine)

    # Should use default registry prefix
    [[ "$output" =~ "ghcr.io/username/repo/hello-world:1.0.0-alpine" ]]
}

#######################################
# Test: Tag output format
#######################################
@test "build_variant_tags outputs tags on separate lines" {
    output=$(build_variant_tags --image hello-world --version 1.0.0 --variant alpine --registry ghcr.io/user/repo)

    # Should have multiple lines
    line_count=$(echo "$output" | wc -l)
    [[ $line_count -gt 1 ]]
}

#######################################
# Test: validate_tag function
#######################################
@test "validate_tag accepts valid tags" {
    validate_tag "1.0.0"
    [[ $? -eq 0 ]]

    validate_tag "latest"
    [[ $? -eq 0 ]]

    validate_tag "alpine"
    [[ $? -eq 0 ]]

    validate_tag "v1.2.3"
    [[ $? -eq 0 ]]
}

#######################################
# Test: validate_tag rejects invalid tags
#######################################
@test "validate_tag rejects invalid characters" {
    run validate_tag "invalid/tag"
    [[ $status -eq 1 ]]

    run validate_tag "invalid:tag"
    [[ $status -eq 1 ]]
}

@test "validate_tag rejects empty string" {
    run validate_tag ""
    [[ $status -eq 1 ]]
}
