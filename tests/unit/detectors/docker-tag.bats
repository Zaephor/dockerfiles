#!/usr/bin/env bats
#
# BATS Tests for Docker Tag Detector
#
# Focuses on argument handling and config parsing. Live registry requests are
# exercised in integration, not here.
#

setup() {
  export TEST_DIR="$(mktemp -d)"
  export TEST_CONFIG="${TEST_DIR}/metadata.yaml"

  cat > "$TEST_CONFIG" <<'EOF'
version_source:
  type: docker-tags
  registry: ghcr.io
  image: user/repo/test-image
EOF
}

teardown() {
  rm -rf "$TEST_DIR"
  rm -rf /tmp/version-cache
}

# ============================================================================
# Argument Handling Tests
# ============================================================================

@test "docker-tag detector accepts --config and --image-name" {
  run .github/scripts/detectors/docker_tag.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image
  # Should exit 0, 1, or 2 (valid detector behavior)
  [[ $status -eq 0 || $status -eq 1 || $status -eq 2 ]]
}

@test "docker-tag detector accepts --variant (orchestrator always passes it)" {
  run .github/scripts/detectors/docker_tag.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image \
    --variant default
  # --variant must not be rejected as an unknown argument
  [[ "$output" != *"Unknown argument"* ]]
  # Must not fail as CONFIG_ERROR caused by argument parsing
  [[ "$output" != *'"error_code": "CONFIG_ERROR"'*"Invalid arguments"* ]]
}

@test "docker-tag detector rejects genuinely unknown arguments" {
  run .github/scripts/detectors/docker_tag.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image \
    --bogus value
  [[ "$output" == *"Unknown argument"* || "$output" == *"CONFIG_ERROR"* ]]
  [ "$status" -eq 2 ]
}

@test "docker-tag detector requires --config and --image-name" {
  run .github/scripts/detectors/docker_tag.sh --image-name test-image
  [ "$status" -ne 0 ]
}
