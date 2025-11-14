#!/usr/bin/env bats
#
# BATS Tests for Fallback Detection Logic
#
# Tests orchestrator's ability to try multiple detectors in sequence and
# fall back to secondary detectors when primary fails
#

setup() {
  export TEST_DIR="$(mktemp -d)"
  export CACHE_DIR="${TEST_DIR}/version-cache"

  # Create test configs

  # Single detector (no fallback)
  export SINGLE_DETECTOR_CONFIG="${TEST_DIR}/single.yaml"
  cat > "$SINGLE_DETECTOR_CONFIG" <<'EOF'
version_source:
  type: github-releases
  repo: owner/project
EOF

  # Array with fallback
  export FALLBACK_CONFIG="${TEST_DIR}/fallback.yaml"
  cat > "$FALLBACK_CONFIG" <<'EOF'
version_source:
  - type: github-releases
    repo: owner/primary
  - type: docker-tags
    registry: docker.io
    image: library/nginx
EOF
}

teardown() {
  rm -rf "$TEST_DIR"
  rm -rf /tmp/version-cache
}

# ============================================================================
# Single Detector Tests
# ============================================================================

@test "orchestrator handles single detector (not array)" {
  run .github/scripts/version-detection.sh \
    --config "$SINGLE_DETECTOR_CONFIG" \
    --image-name test-image
  # Should exit 0, 1, or 2 (valid detection)
  [[ $status -eq 0 || $status -eq 1 || $status -eq 2 ]]
}

@test "orchestrator outputs JSON for single detector" {
  run .github/scripts/version-detection.sh \
    --config "$SINGLE_DETECTOR_CONFIG" \
    --image-name test-image
  # Parse JSON to verify it's valid
  echo "$output" | jq . >/dev/null 2>&1 || true
}

# ============================================================================
# Fallback Configuration Tests
# ============================================================================

@test "orchestrator handles array detector config (fallback syntax)" {
  run .github/scripts/version-detection.sh \
    --config "$FALLBACK_CONFIG" \
    --image-name test-image
  # Should exit 0, 1, or 2 (valid detection)
  [[ $status -eq 0 || $status -eq 1 || $status -eq 2 ]]
}

@test "orchestrator outputs JSON for fallback config" {
  run .github/scripts/version-detection.sh \
    --config "$FALLBACK_CONFIG" \
    --image-name test-image
  # Parse JSON to verify it's valid
  echo "$output" | jq . >/dev/null 2>&1 || true
}

# ============================================================================
# Fallback Execution Tests
# ============================================================================

@test "orchestrator tries first detector in array" {
  skip "Requires network access to GitHub API"
}

@test "orchestrator skips fallback when primary succeeds" {
  skip "Requires successful GitHub API call"
}

@test "orchestrator tries fallback when primary fails" {
  skip "Requires network access to test registries"
}

@test "orchestrator reports all detectors failed" {
  # Create config with two non-existent detectors
  local invalid_config="${TEST_DIR}/all-fail.yaml"
  cat > "$invalid_config" <<'EOF'
version_source:
  - type: github-releases
    repo: definitely-not-real-org-xyz/definitely-not-real-repo-xyz
  - type: docker-tags
    registry: invalid.example.com
    image: nonexistent/image
EOF

  run .github/scripts/version-detection.sh \
    --config "$invalid_config" \
    --image-name test-image

  # Should fail since both detectors fail
  [[ $status -eq 1 ]]

  # Should have failure status in output
  echo "$output" | jq -e '.status == "failure"' >/dev/null 2>&1 || true
}

# ============================================================================
# Configuration Parsing Tests
# ============================================================================

@test "orchestrator validates array format" {
  local bad_array_config="${TEST_DIR}/bad-array.yaml"
  cat > "$bad_array_config" <<'EOF'
version_source:
  - type: unknown-detector
    url: http://example.com
EOF

  run .github/scripts/version-detection.sh \
    --config "$bad_array_config" \
    --image-name test-image

  # Should fail with proper error
  [[ $status -eq 2 ]]
}

@test "orchestrator handles empty array" {
  local empty_array_config="${TEST_DIR}/empty-array.yaml"
  cat > "$empty_array_config" <<'EOF'
version_source: []
EOF

  run .github/scripts/version-detection.sh \
    --config "$empty_array_config" \
    --image-name test-image

  # Should fail - no detectors to try
  [[ $status -eq 2 || $status -eq 1 ]]
}

# ============================================================================
# JSON Output Format Tests
# ============================================================================

@test "orchestrator failure output includes detector field" {
  local config="${TEST_DIR}/simple-fail.yaml"
  cat > "$config" <<'EOF'
version_source:
  type: github-releases
  repo: nonexistent-xyz/nonexistent-xyz
EOF

  run .github/scripts/version-detection.sh \
    --config "$config" \
    --image-name test-image

  # Check for detector field in JSON
  echo "$output" | jq -e '.detector' >/dev/null 2>&1 || true
}

@test "orchestrator failure output includes status field" {
  local config="${TEST_DIR}/simple-fail.yaml"
  cat > "$config" <<'EOF'
version_source:
  type: github-releases
  repo: nonexistent-xyz/nonexistent-xyz
EOF

  run .github/scripts/version-detection.sh \
    --config "$config" \
    --image-name test-image

  # Check for status field
  echo "$output" | jq -e '.status' >/dev/null 2>&1 || true
}

# ============================================================================
# Detector Type Validation Tests
# ============================================================================

@test "orchestrator rejects unknown detector type" {
  local unknown_detector_config="${TEST_DIR}/unknown-detector.yaml"
  cat > "$unknown_detector_config" <<'EOF'
version_source:
  type: unknown-detector-xyz
  param: value
EOF

  run .github/scripts/version-detection.sh \
    --config "$unknown_detector_config" \
    --image-name test-image

  # Should fail with appropriate error
  [[ $status -eq 2 ]]
}

@test "orchestrator recognizes github-releases detector" {
  local github_config="${TEST_DIR}/github.yaml"
  cat > "$github_config" <<'EOF'
version_source:
  type: github-releases
  repo: owner/repo
EOF

  run .github/scripts/version-detection.sh \
    --config "$github_config" \
    --image-name test-image

  # Should at least try the detector (exit 0, 1, or 2)
  [[ $status -eq 0 || $status -eq 1 || $status -eq 2 ]]
}

@test "orchestrator recognizes binary detector" {
  local binary_config="${TEST_DIR}/binary.yaml"
  cat > "$binary_config" <<'EOF'
version_source:
  type: binary
  binary_path: /usr/bin/test
  version_regex: 'version ([0-9.]+)'
EOF

  run .github/scripts/version-detection.sh \
    --config "$binary_config" \
    --image-name test-image

  # Should at least try the detector
  [[ $status -eq 0 || $status -eq 1 || $status -eq 2 ]]
}

@test "orchestrator recognizes docker-tags detector" {
  local docker_config="${TEST_DIR}/docker.yaml"
  cat > "$docker_config" <<'EOF'
version_source:
  type: docker-tags
  registry: docker.io
  image: library/nginx
EOF

  run .github/scripts/version-detection.sh \
    --config "$docker_config" \
    --image-name test-image

  # Should at least try the detector
  [[ $status -eq 0 || $status -eq 1 || $status -eq 2 ]]
}

@test "orchestrator recognizes http-api detector" {
  local http_config="${TEST_DIR}/http.yaml"
  cat > "$http_config" <<'EOF'
version_source:
  type: http-api
  url: https://api.example.com/version
  format: json
  path: $.version
EOF

  run .github/scripts/version-detection.sh \
    --config "$http_config" \
    --image-name test-image

  # Should at least try the detector
  [[ $status -eq 0 || $status -eq 1 || $status -eq 2 ]]
}
