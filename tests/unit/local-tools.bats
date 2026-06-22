#!/usr/bin/env bats
# BATS tests for local testing scripts
# Run with: bats tests/unit/local-tools.bats

setup() {
    # Create temporary test directory
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR
    # Save project root for script references
    PROJECT_ROOT="$(pwd)"
    export PROJECT_ROOT
}

teardown() {
    # Clean up test directory
    rm -rf "$TEST_DIR"
}

# Tests for validate-metadata.sh

@test "validate-metadata.sh shows help" {
    run .github/scripts/local-tools/validate-metadata.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "validate-metadata.sh fails with missing arguments" {
    run .github/scripts/local-tools/validate-metadata.sh
    [ "$status" -eq 3 ]
}

@test "validate-metadata.sh fails when image directory not found" {
    run .github/scripts/local-tools/validate-metadata.sh nonexistent-image
    [ "$status" -eq 4 ]
}

@test "validate-metadata.sh fails with invalid metadata" {
    mkdir -p "$TEST_DIR/test-image"
    cat > "$TEST_DIR/test-image/Dockerfile" <<EOF
FROM alpine:latest
EOF
    cat > "$TEST_DIR/test-image/metadata.yaml" <<EOF
invalid: yaml: format:
  - broken
EOF
    cd "$TEST_DIR"
    run "$PROJECT_ROOT/.github/scripts/local-tools/validate-metadata.sh" test-image
    [ "$status" -eq 1 ]
}

@test "validate-metadata.sh passes with valid minimal metadata" {
    mkdir -p "$TEST_DIR/test-image"
    cat > "$TEST_DIR/test-image/Dockerfile" <<EOF
FROM alpine:latest
EOF
    cat > "$TEST_DIR/test-image/metadata.yaml" <<EOF
name: test-image
version_source:
  type: github_releases
  repo: owner/repo
EOF
    cd "$TEST_DIR/test-image"
    run "$PROJECT_ROOT/.github/scripts/local-tools/validate-metadata.sh" test-image
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Metadata validation passed" ]]
}

# Tests for test-version-detection.sh

@test "test-version-detection.sh shows help" {
    run .github/scripts/local-tools/test-version-detection.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "test-version-detection.sh fails when metadata not found" {
    run .github/scripts/local-tools/test-version-detection.sh nonexistent
    [ "$status" -eq 4 ]
}

# Tests for check-conditional-build.sh

@test "check-conditional-build.sh shows help" {
    run .github/scripts/local-tools/check-conditional-build.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "check-conditional-build.sh indicates first build would happen" {
    mkdir -p "$TEST_DIR/test-image"
    cat > "$TEST_DIR/test-image/Dockerfile" <<EOF
FROM alpine:latest
EOF
    cat > "$TEST_DIR/test-image/metadata.yaml" <<EOF
name: test-image
version_source:
  type: github_releases
  repo: owner/repo
EOF
    cd "$TEST_DIR"
    run "$PROJECT_ROOT/.github/scripts/local-tools/check-conditional-build.sh" test-image
    [ "$status" -eq 0 ]
    [[ "$output" =~ "WOULD BE BUILT" ]] || [[ "$output" =~ "would" ]]
}

# Tests for lint-dockerfile.sh

@test "lint-dockerfile.sh shows help" {
    run .github/scripts/local-tools/lint-dockerfile.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "lint-dockerfile.sh fails when no Dockerfile found" {
    mkdir -p "$TEST_DIR/empty-image"
    cd "$TEST_DIR"
    run "$PROJECT_ROOT/.github/scripts/local-tools/lint-dockerfile.sh" empty-image
    # If hadolint is not available, test is skipped (status 0 with SKIP message)
    # If hadolint is available, missing Dockerfile returns 4
    if [[ "$output" =~ "SKIP" ]]; then
        [ "$status" -eq 0 ]
    else
        [ "$status" -eq 4 ]
    fi
}

@test "lint-dockerfile.sh passes with valid Dockerfile" {
    mkdir -p "$TEST_DIR/valid-image"
    cat > "$TEST_DIR/valid-image/Dockerfile" <<EOF
FROM alpine:3.18
RUN apk add --no-cache ca-certificates=20240726-r0
ENTRYPOINT ["cat"]
EOF
    cat > "$TEST_DIR/valid-image/metadata.yaml" <<EOF
name: valid-image
version_source:
  type: docker_tag
  registry: docker.io
  image: library/alpine
EOF
    cd "$TEST_DIR"
    run "$PROJECT_ROOT/.github/scripts/local-tools/lint-dockerfile.sh" valid-image
    # Test passes if hadolint is not available (skipped) or linting succeeds
    if [[ "$output" =~ "SKIP" ]]; then
        [ "$status" -eq 0 ]
    else
        [ "$status" -eq 0 ]
    fi
}

# Tests for lib/local-common.sh

@test "find_image_dir finds image in current directory" {
    mkdir -p "$TEST_DIR/test-image"
    touch "$TEST_DIR/test-image/Dockerfile"
    touch "$TEST_DIR/test-image/metadata.yaml"
    cd "$TEST_DIR/test-image"

    source "$PROJECT_ROOT/.github/scripts/local-tools/lib/local-common.sh"
    result=$(find_image_dir . 2>/dev/null || echo "")
    [ -n "$result" ]
}
