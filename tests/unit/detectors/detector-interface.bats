#!/usr/bin/env bats
#
# BATS Tests for Detector Interface Contract
#
# Validates that all detectors conform to the standard interface
#

setup() {
  export TEST_DIR="$(mktemp -d)"
  export TEST_CONFIG="${TEST_DIR}/metadata.yaml"

  # Create a minimal valid test config (github-releases)
  cat > "$TEST_CONFIG" <<'EOF'
version_source:
  type: github-releases
  repo: owner/test-project
EOF
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ============================================================================
# Argument Parsing Tests
# ============================================================================

@test "detector requires --config argument" {
  run .github/scripts/detectors/detector-interface.sh --image-name test-image
  [[ $status -ne 0 ]]
  [[ "$output" =~ "Missing required arguments" ]]
}

@test "detector requires --image-name argument" {
  run .github/scripts/detectors/detector-interface.sh --config "$TEST_CONFIG"
  [[ $status -ne 0 ]]
  [[ "$output" =~ "Missing required arguments" ]]
}

@test "detector requires both --config and --image-name arguments" {
  run .github/scripts/detectors/detector-interface.sh
  [[ $status -eq 2 ]]
  [[ "$output" =~ "Missing required arguments" || "$output" =~ "CONFIG_ERROR" ]]
}

@test "detector accepts --config and --image-name arguments" {
  run .github/scripts/detectors/detector-interface.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image
  # May succeed or fail, but should exit 0, 1, or 2 (not error from arg parsing)
  [[ $status -eq 0 || $status -eq 1 || $status -eq 2 ]]
}

@test "detector rejects unknown arguments" {
  run .github/scripts/detectors/detector-interface.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image \
    --unknown-arg value
  [[ $status -eq 2 ]]
  [[ "$output" =~ "Unknown argument" ]]
}

# ============================================================================
# Output Format Tests
# ============================================================================

@test "detector outputs JSON on failure" {
  run .github/scripts/detectors/detector-interface.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image
  # Parse output as JSON (should be valid)
  echo "$output" | jq . >/dev/null
}

@test "detector JSON includes status field" {
  run .github/scripts/detectors/detector-interface.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image
  echo "$output" | jq -e '.status' >/dev/null
}

@test "detector JSON includes version field" {
  run .github/scripts/detectors/detector-interface.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image
  echo "$output" | jq -e '.version' >/dev/null
}

@test "detector JSON includes detector field" {
  run .github/scripts/detectors/detector-interface.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image
  echo "$output" | jq -e '.detector' >/dev/null
}

# ============================================================================
# Exit Code Tests
# ============================================================================

@test "detector exits with 0, 1, or 2" {
  run .github/scripts/detectors/detector-interface.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image
  [[ $status -eq 0 || $status -eq 1 || $status -eq 2 ]]
}

@test "detector exits with 2 on missing config file" {
  run .github/scripts/detectors/detector-interface.sh \
    --config /nonexistent/metadata.yaml \
    --image-name test-image
  [[ $status -eq 2 ]]
}

@test "detector exits with 2 on missing required argument" {
  run .github/scripts/detectors/detector-interface.sh \
    --config "$TEST_CONFIG"
  [[ $status -eq 2 ]]
}

# ============================================================================
# Success Output Format Tests
# ============================================================================

@test "detector success output has status: success" {
  # This test would need a config that actually succeeds
  # For interface testing, we test the structure
  skip "Requires real detector with successful API call"
}

@test "detector success output has non-null version" {
  skip "Requires real detector with successful API call"
}

@test "detector success output has cached field (boolean)" {
  skip "Requires real detector with successful API call"
}

# ============================================================================
# Failure Output Format Tests
# ============================================================================

@test "detector failure output has status: failure" {
  # Create config with invalid repo format
  local invalid_config="${TEST_DIR}/invalid-metadata.yaml"
  cat > "$invalid_config" <<'EOF'
version_source:
  type: github-releases
  repo: invalid
EOF
  run .github/scripts/detectors/detector-interface.sh \
    --config "$invalid_config" \
    --image-name test-image
  echo "$output" | jq -e '.status == "failure"' >/dev/null
}

@test "detector failure output has null version" {
  local invalid_config="${TEST_DIR}/invalid-metadata.yaml"
  cat > "$invalid_config" <<'EOF'
version_source:
  type: github-releases
  repo: invalid
EOF
  run .github/scripts/detectors/detector-interface.sh \
    --config "$invalid_config" \
    --image-name test-image
  echo "$output" | jq -e '.version == null' >/dev/null
}

@test "detector failure output has error field" {
  local invalid_config="${TEST_DIR}/invalid-metadata.yaml"
  cat > "$invalid_config" <<'EOF'
version_source:
  type: github-releases
  repo: invalid
EOF
  run .github/scripts/detectors/detector-interface.sh \
    --config "$invalid_config" \
    --image-name test-image
  echo "$output" | jq -e '.error' >/dev/null
}

@test "detector failure output has error_code field" {
  local invalid_config="${TEST_DIR}/invalid-metadata.yaml"
  cat > "$invalid_config" <<'EOF'
version_source:
  type: github-releases
  repo: invalid
EOF
  run .github/scripts/detectors/detector-interface.sh \
    --config "$invalid_config" \
    --image-name test-image
  echo "$output" | jq -e '.error_code' >/dev/null
}

# ============================================================================
# Standard Error Codes Tests
# ============================================================================

@test "detector returns standard error codes (CONFIG_ERROR)" {
  # Missing required field should return CONFIG_ERROR
  local missing_field_config="${TEST_DIR}/missing-field.yaml"
  cat > "$missing_field_config" <<'EOF'
version_source:
  type: github-releases
EOF
  run .github/scripts/detectors/detector-interface.sh \
    --config "$missing_field_config" \
    --image-name test-image
  [[ $status -eq 2 ]]
  echo "$output" | jq -e '.error_code == "CONFIG_ERROR"' >/dev/null
}

# ============================================================================
# JSON Validity Tests
# ============================================================================

@test "detector JSON output is valid and parseable" {
  run .github/scripts/detectors/detector-interface.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image
  echo "$output" | jq . >/dev/null 2>&1
}

@test "detector JSON output contains no trailing garbage" {
  run .github/scripts/detectors/detector-interface.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image
  # Count JSON objects (should be exactly 1)
  local count
  count=$(echo "$output" | jq . 2>/dev/null | grep -c '^{' || echo 0)
  [[ $count -eq 1 ]]
}
