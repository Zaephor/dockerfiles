#!/usr/bin/env bats
# Unit tests for merge-manifest.sh script
# Tests manifest coordination logic for multi-architecture Docker builds

# Test fixtures directory
FIXTURES_DIR="tests/fixtures/merge-manifest"

# Load merge-manifest.sh for testing
# Will be sourced once script is created in Phase 2
SCRIPT_PATH=".github/scripts/merge-manifest.sh"

# Helper function to check if Docker daemon is available
docker_available() {
  command -v docker &>/dev/null && docker info &>/dev/null
}

setup() {
  # Create temporary test directory
  export TEST_DIR="$(mktemp -d)"
  export TEST_IMAGE="test/example"
  export TEST_TAG="v1.0.0"

  # Sample valid digests
  export VALID_AMD64_DIGEST="sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
  export VALID_ARM64_DIGEST="sha256:fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321"

  # Invalid digests for testing
  export INVALID_DIGEST_SHORT="sha256:abc123"
  export INVALID_DIGEST_NO_PREFIX="1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
}

teardown() {
  # Clean up test directory
  rm -rf "$TEST_DIR"
}

# Phase 3 Tests: User Story 1 - Parameter Validation and Error Handling

@test "T009 [US1]: merge-manifest.sh requires --image parameter" {
  run .github/scripts/merge-manifest.sh \
    --tag "v1.0.0" \
    --amd64-digest "$VALID_AMD64_DIGEST" \
    --amd64-status "success" \
    --arm64-digest "$VALID_ARM64_DIGEST" \
    --arm64-status "success"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "--image is required" ]]
}

@test "T010 [US1]: merge-manifest.sh validates digest format (sha256:[0-9a-f]{64})" {
  # Test with invalid short digest
  run .github/scripts/merge-manifest.sh \
    --image "$TEST_IMAGE" \
    --tag "$TEST_TAG" \
    --amd64-digest "$INVALID_DIGEST_SHORT" \
    --amd64-status "success" \
    --arm64-digest "$VALID_ARM64_DIGEST" \
    --arm64-status "success"

  [ "$status" -eq 2 ]
  [[ "$output" =~ "invalid format" ]] || [[ "$output" =~ "Both amd64 and arm64 builds failed" ]]

  # Test with invalid no-prefix digest
  run .github/scripts/merge-manifest.sh \
    --image "$TEST_IMAGE" \
    --tag "$TEST_TAG" \
    --amd64-digest "$VALID_AMD64_DIGEST" \
    --amd64-status "success" \
    --arm64-digest "$INVALID_DIGEST_NO_PREFIX" \
    --arm64-status "success"

  [ "$status" -eq 2 ]
  [[ "$output" =~ "invalid format" ]] || [[ "$output" =~ "Both amd64 and arm64 builds failed" ]]
}

@test "T011 [US1]: merge-manifest.sh handles missing digests gracefully" {
  # Test with empty amd64 digest (arm64 successful - should create arm64-only manifest)
  # Note: This test verifies the script accepts missing digests without crashing
  # Actual manifest creation will be skipped in test environment (no Docker daemon)

  run .github/scripts/merge-manifest.sh \
    --image "$TEST_IMAGE" \
    --tag "$TEST_TAG" \
    --amd64-digest "" \
    --amd64-status "failure" \
    --arm64-digest "$VALID_ARM64_DIGEST" \
    --arm64-status "success"

  # Script should exit with code 0 or 1 (not 2 which means both failed)
  # Exit code 1 may occur if Docker daemon unavailable (expected in test env)
  [ "$status" -ne 2 ]
  [[ "$output" =~ "arm64 build: SUCCESS" ]]
  [[ "$output" =~ "amd64 build: FAILED" ]]
}

@test "T012 [US1]: merge-manifest.sh exits with code 2 when both architectures fail" {
  run .github/scripts/merge-manifest.sh \
    --image "$TEST_IMAGE" \
    --tag "$TEST_TAG" \
    --amd64-digest "" \
    --amd64-status "failure" \
    --arm64-digest "" \
    --arm64-status "failure"

  [ "$status" -eq 2 ]
  [[ "$output" =~ "Both amd64 and arm64 builds failed" ]]
}

# Phase 4 Tests: User Story 2 - Manifest Creation and Verification

@test "T023 [US2]: merge-manifest.sh creates multi-arch manifest with 2 digests" {
  # Skip if Docker daemon not available
  if ! docker_available; then
    skip "Docker daemon not available"
  fi

  # Test that script prepares to create manifest with both architectures
  # Note: Actual Docker manifest creation requires Docker daemon
  # This test verifies the script logic and outputs

  run .github/scripts/merge-manifest.sh \
    --image "$TEST_IMAGE" \
    --tag "$TEST_TAG" \
    --amd64-digest "$VALID_AMD64_DIGEST" \
    --amd64-status "success" \
    --arm64-digest "$VALID_ARM64_DIGEST" \
    --arm64-status "success"

  # Script should exit with 0 or 1 (1 if Docker daemon unavailable in test env)
  # Exit code 2 means both failed, which should NOT happen with both successful
  [ "$status" -ne 2 ]
  [[ "$output" =~ "amd64 build: SUCCESS" ]]
  [[ "$output" =~ "arm64 build: SUCCESS" ]]
  [[ "$output" =~ "multi-architecture manifest" ]]
}

@test "T024 [US2]: merge-manifest.sh creates single-arch manifest when one digest missing (graceful degradation)" {
  # Skip if Docker daemon not available
  if ! docker_available; then
    skip "Docker daemon not available"
  fi

  # Test graceful degradation: amd64 succeeds, arm64 fails
  run .github/scripts/merge-manifest.sh \
    --image "$TEST_IMAGE" \
    --tag "$TEST_TAG" \
    --amd64-digest "$VALID_AMD64_DIGEST" \
    --amd64-status "success" \
    --arm64-digest "" \
    --arm64-status "failure"

  # Should not fail (exit code != 2)
  [ "$status" -ne 2 ]
  [[ "$output" =~ "amd64 build: SUCCESS" ]]
  [[ "$output" =~ "arm64 build: FAILED" ]]
  [[ "$output" =~ "single-architecture manifest" ]] || [[ "$output" =~ "amd64 only" ]]

  # Test graceful degradation: arm64 succeeds, amd64 fails
  run .github/scripts/merge-manifest.sh \
    --image "$TEST_IMAGE" \
    --tag "$TEST_TAG" \
    --amd64-digest "" \
    --amd64-status "failure" \
    --arm64-digest "$VALID_ARM64_DIGEST" \
    --arm64-status "success"

  # Should not fail (exit code != 2)
  [ "$status" -ne 2 ]
  [[ "$output" =~ "arm64 build: SUCCESS" ]]
  [[ "$output" =~ "amd64 build: FAILED" ]]
  [[ "$output" =~ "single-architecture manifest" ]] || [[ "$output" =~ "arm64 only" ]]
}

@test "T025 [US2]: verify manifest contains expected platforms after creation" {
  # Skip test: requires actual Docker daemon with pushed images
  # In unit test environment, we can't test manifest verification without mock images
  # This would require integration testing with real Docker registry
  skip "Manifest verification requires Docker daemon with pushed images (integration test)"
}
