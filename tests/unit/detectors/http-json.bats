#!/usr/bin/env bats
#
# BATS Tests for HTTP JSON Detector
#
# Focuses on argument handling and config parsing. Live HTTP requests are
# exercised in integration, not here.
#

setup() {
  export TEST_DIR="$(mktemp -d)"
  export TEST_CONFIG="${TEST_DIR}/metadata.yaml"

  cat > "$TEST_CONFIG" <<'EOF'
version_source:
  type: http-api
  url: https://api.example.com/releases/latest
  format: json
  path: $.version
EOF
}

teardown() {
  rm -rf "$TEST_DIR"
  rm -rf /tmp/version-cache
}

# ============================================================================
# Argument Handling Tests
# ============================================================================

@test "http-json detector accepts --config and --image-name" {
  run .github/scripts/detectors/http_json.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image
  # Should exit 0, 1, or 2 (valid detector behavior)
  [[ $status -eq 0 || $status -eq 1 || $status -eq 2 ]]
}

@test "http-json detector accepts --variant (orchestrator always passes it)" {
  run .github/scripts/detectors/http_json.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image \
    --variant default
  # --variant must not be rejected as an unknown argument
  [[ "$output" != *"Unknown argument"* ]]
  # Must not fail as CONFIG_ERROR caused by argument parsing
  [[ "$output" != *'"error_code": "CONFIG_ERROR"'*"Invalid arguments"* ]]
}

@test "http-json detector rejects genuinely unknown arguments" {
  run .github/scripts/detectors/http_json.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image \
    --bogus value
  [[ "$output" == *"Unknown argument"* || "$output" == *"CONFIG_ERROR"* ]]
  [ "$status" -eq 2 ]
}

@test "http-json detector requires --config and --image-name" {
  run .github/scripts/detectors/http_json.sh --image-name test-image
  [ "$status" -ne 0 ]
}

# ============================================================================
# Detection Tests (hermetic, via file:// URL)
# ============================================================================

@test "http-json detector detects version from JSON endpoint end-to-end" {
  cat > "${TEST_DIR}/api.json" <<'EOF'
{"version": "1.2.3", "name": "test"}
EOF

  cat > "$TEST_CONFIG" <<EOF
version_source:
  type: http-api
  url: file://${TEST_DIR}/api.json
  format: json
  path: .version
EOF

  run .github/scripts/detectors/http_json.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image
  [ "$status" -eq 0 ]

  # Extract the JSON document (skip INFO log lines on stderr)
  json=$(echo "$output" | sed -n '/^{/,$p')
  version=$(echo "$json" | jq -r '.version')
  [ "$version" = "1.2.3" ]

  source_url=$(echo "$json" | jq -r '.metadata.source_url')
  [ "$source_url" = "file://${TEST_DIR}/api.json" ]
}

@test "http-json detector accepts dollar-prefixed JSONPath ($.version)" {
  cat > "${TEST_DIR}/api.json" <<'EOF'
{"version": "2.0.0", "name": "test"}
EOF

  cat > "$TEST_CONFIG" <<EOF
version_source:
  type: http-api
  url: file://${TEST_DIR}/api.json
  format: json
  path: $.version
EOF

  run .github/scripts/detectors/http_json.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image
  [ "$status" -eq 0 ]

  json=$(echo "$output" | sed -n '/^{/,$p')
  version=$(echo "$json" | jq -r '.version')
  [ "$version" = "2.0.0" ]
}
