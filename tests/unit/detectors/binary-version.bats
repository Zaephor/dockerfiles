#!/usr/bin/env bats
#
# BATS Tests for Binary Version Detector
#
# Focuses on argument handling and config parsing. Actual version extraction
# requires building a container (docker) and is exercised in integration, not
# here.
#

setup() {
  export TEST_DIR="$(mktemp -d)"
  export TEST_CONFIG="${TEST_DIR}/metadata.yaml"

  # Map-schema config (the form the orchestrator and detector actually read)
  cat > "$TEST_CONFIG" <<'EOF'
version_source:
  type: binary_version
  binary_path: /usr/sbin/slapd
  version_flags: -VV
  version_regex: 'slapd ([0-9]+\.[0-9]+\.[0-9]+)'
EOF
}

teardown() {
  rm -rf "$TEST_DIR"
  rm -rf /tmp/version-cache
}

# ============================================================================
# Argument Handling Tests
# ============================================================================

@test "binary-version detector accepts --variant (orchestrator always passes it)" {
  run .github/scripts/detectors/binary_version.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image \
    --variant default
  # --variant must not be rejected as an unknown argument
  [[ "$output" != *"Unknown argument"* ]]
  # Must not fail as a CONFIG_ERROR caused by argument parsing
  [[ "$output" != *'"error_code": "CONFIG_ERROR"'*"Invalid arguments"* ]]
}

@test "binary-version detector rejects genuinely unknown arguments" {
  run .github/scripts/detectors/binary_version.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image \
    --bogus value
  [[ "$output" == *"Unknown argument"* || "$output" == *"CONFIG_ERROR"* ]]
  [ "$status" -eq 2 ]
}

@test "binary-version detector requires --config and --image-name" {
  run .github/scripts/detectors/binary_version.sh --image-name test-image
  [ "$status" -ne 0 ]
}
