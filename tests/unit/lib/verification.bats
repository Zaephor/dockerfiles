#!/usr/bin/env bats
# verification.bats - Unit tests for container verification library
#
# Tests verification configuration parsing, validation, and mode handlers
#

setup() {
  # Load the verification library
  source .github/scripts/lib/verification.sh

  # Create temp directory for test artifacts
  export TEST_DIR="$(mktemp -d)"
}

teardown() {
  # Clean up test directory
  rm -rf "$TEST_DIR"
}

# ============================================================================
# parse_verification_config tests
# ============================================================================

@test "parse_verification_config: returns empty object for missing verification section" {
  local metadata_file="$TEST_DIR/metadata.yaml"
  cat > "$metadata_file" << 'EOF'
name: test-image
version_source:
  type: github_releases
EOF

  run parse_verification_config "$metadata_file"
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "parse_verification_config: parses python-cli mode correctly" {
  local metadata_file="$TEST_DIR/metadata.yaml"
  cat > "$metadata_file" << 'EOF'
name: test-image
verification:
  mode: python-cli
  module: my_module
  help_command: python3 -m my_module --help
EOF

  run parse_verification_config "$metadata_file"
  [ "$status" -eq 0 ]

  # Check parsed values
  local mode
  mode=$(echo "$output" | jq -r '.mode')
  [ "$mode" = "python-cli" ]

  local module
  module=$(echo "$output" | jq -r '.module')
  [ "$module" = "my_module" ]
}

@test "parse_verification_config: parses command mode with multiple commands" {
  local metadata_file="$TEST_DIR/metadata.yaml"
  cat > "$metadata_file" << 'EOF'
name: test-image
verification:
  mode: command
  commands:
    - name: Import check
      run: python3 -c "import mymodule"
    - name: CLI responds
      run: myapp --help
      stdout_contains: "usage:"
EOF

  run parse_verification_config "$metadata_file"
  [ "$status" -eq 0 ]

  local mode
  mode=$(echo "$output" | jq -r '.mode')
  [ "$mode" = "command" ]

  local command_count
  command_count=$(echo "$output" | jq '.commands | length')
  [ "$command_count" -eq 2 ]

  local first_name
  first_name=$(echo "$output" | jq -r '.commands[0].name')
  [ "$first_name" = "Import check" ]
}

@test "parse_verification_config: parses port mode correctly" {
  local metadata_file="$TEST_DIR/metadata.yaml"
  cat > "$metadata_file" << 'EOF'
name: test-image
verification:
  mode: port
  port: 8080
  startup_timeout: 30
  health_path: /health
EOF

  run parse_verification_config "$metadata_file"
  [ "$status" -eq 0 ]

  local mode
  mode=$(echo "$output" | jq -r '.mode')
  [ "$mode" = "port" ]

  local port
  port=$(echo "$output" | jq -r '.port')
  [ "$port" = "8080" ]

  local health_path
  health_path=$(echo "$output" | jq -r '.health_path')
  [ "$health_path" = "/health" ]
}

@test "parse_verification_config: parses none mode with reason" {
  local metadata_file="$TEST_DIR/metadata.yaml"
  cat > "$metadata_file" << 'EOF'
name: test-image
verification:
  mode: none
  reason: "Requires external hardware"
EOF

  run parse_verification_config "$metadata_file"
  [ "$status" -eq 0 ]

  local mode
  mode=$(echo "$output" | jq -r '.mode')
  [ "$mode" = "none" ]

  local reason
  reason=$(echo "$output" | jq -r '.reason')
  [ "$reason" = "Requires external hardware" ]
}

@test "parse_verification_config: returns error for missing file" {
  run parse_verification_config "$TEST_DIR/nonexistent.yaml"
  [ "$status" -eq 2 ]
}

# ============================================================================
# get_verification_mode tests
# ============================================================================

@test "get_verification_mode: extracts mode from config" {
  local config='{"mode": "python-cli", "module": "test"}'

  run get_verification_mode "$config"
  [ "$status" -eq 0 ]
  [ "$output" = "python-cli" ]
}

@test "get_verification_mode: returns empty for missing mode" {
  local config='{}'

  run get_verification_mode "$config"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

# ============================================================================
# validate_verification_config tests
# ============================================================================

@test "validate_verification_config: accepts empty config (backwards compatible)" {
  local config='{}'

  run validate_verification_config "$config"
  [ "$status" -eq 0 ]
}

@test "validate_verification_config: accepts none mode" {
  local config='{"mode": "none"}'

  run validate_verification_config "$config"
  [ "$status" -eq 0 ]
}

@test "validate_verification_config: accepts valid python-cli config" {
  local config='{"mode": "python-cli", "module": "my_module"}'

  run validate_verification_config "$config"
  [ "$status" -eq 0 ]
}

@test "validate_verification_config: rejects python-cli without module" {
  local config='{"mode": "python-cli"}'

  run validate_verification_config "$config"
  [ "$status" -eq 2 ]
  [[ "$output" =~ "module" ]]
}

@test "validate_verification_config: accepts valid binary config" {
  local config='{"mode": "binary", "binary": "/usr/local/bin/myapp"}'

  run validate_verification_config "$config"
  [ "$status" -eq 0 ]
}

@test "validate_verification_config: rejects binary without binary field" {
  local config='{"mode": "binary"}'

  run validate_verification_config "$config"
  [ "$status" -eq 2 ]
  [[ "$output" =~ "binary" ]]
}

@test "validate_verification_config: accepts valid command config" {
  local config='{"mode": "command", "commands": [{"name": "test", "run": "echo hello"}]}'

  run validate_verification_config "$config"
  [ "$status" -eq 0 ]
}

@test "validate_verification_config: rejects command without commands array" {
  local config='{"mode": "command"}'

  run validate_verification_config "$config"
  [ "$status" -eq 2 ]
  [[ "$output" =~ "commands" ]]
}

@test "validate_verification_config: accepts valid port config" {
  local config='{"mode": "port", "port": 8080}'

  run validate_verification_config "$config"
  [ "$status" -eq 0 ]
}

@test "validate_verification_config: rejects port without port field" {
  local config='{"mode": "port"}'

  run validate_verification_config "$config"
  [ "$status" -eq 2 ]
  [[ "$output" =~ "port" ]]
}

@test "validate_verification_config: rejects invalid port number (0)" {
  local config='{"mode": "port", "port": 0}'

  run validate_verification_config "$config"
  [ "$status" -eq 2 ]
  [[ "$output" =~ "port" ]]
}

@test "validate_verification_config: rejects invalid port number (too high)" {
  local config='{"mode": "port", "port": 70000}'

  run validate_verification_config "$config"
  [ "$status" -eq 2 ]
  [[ "$output" =~ "port" ]]
}

@test "validate_verification_config: rejects invalid mode" {
  local config='{"mode": "invalid-mode"}'

  run validate_verification_config "$config"
  [ "$status" -eq 2 ]
  [[ "$output" =~ "Invalid verification mode" ]]
}

# ============================================================================
# check_stdout_contains tests
# ============================================================================

@test "check_stdout_contains: returns 0 when string is found" {
  run check_stdout_contains "hello world" "world"
  [ "$status" -eq 0 ]
}

@test "check_stdout_contains: returns 1 when string not found" {
  run check_stdout_contains "hello world" "foo"
  [ "$status" -eq 1 ]
}

@test "check_stdout_contains: handles multi-line output" {
  local output="line 1
line 2
line 3 contains target"

  run check_stdout_contains "$output" "target"
  [ "$status" -eq 0 ]
}

# ============================================================================
# output_json_result tests
# ============================================================================

@test "output_json_result: produces valid JSON with all fields" {
  run output_json_result "test-image" "1.0.0" "python-cli" "passed" "Success" 0
  [ "$status" -eq 0 ]

  # Validate JSON
  echo "$output" | jq . >/dev/null

  local image
  image=$(echo "$output" | jq -r '.image')
  [ "$image" = "test-image" ]

  local tag
  tag=$(echo "$output" | jq -r '.tag')
  [ "$tag" = "1.0.0" ]

  local mode
  mode=$(echo "$output" | jq -r '.verification.mode')
  [ "$mode" = "python-cli" ]

  local status_val
  status_val=$(echo "$output" | jq -r '.verification.status')
  [ "$status_val" = "passed" ]

  local exit_code
  exit_code=$(echo "$output" | jq -r '.verification.exit_code')
  [ "$exit_code" = "0" ]
}

@test "output_json_result: handles failure status correctly" {
  run output_json_result "test-image" "2.0.0" "command" "failed" "Verification failed" 1
  [ "$status" -eq 0 ]

  local status_val
  status_val=$(echo "$output" | jq -r '.verification.status')
  [ "$status_val" = "failed" ]

  local exit_code
  exit_code=$(echo "$output" | jq -r '.verification.exit_code')
  [ "$exit_code" = "1" ]
}

# ============================================================================
# Integration tests (run_verification with mock metadata)
# ============================================================================

@test "run_verification: skips with warning when no verification config" {
  local metadata_file="$TEST_DIR/metadata.yaml"
  cat > "$metadata_file" << 'EOF'
name: test-image
version_source:
  type: github_releases
EOF

  run run_verification "test-image" "1.0.0" "$metadata_file"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "WARNING" ]]
  [[ "$output" =~ "No verification config" ]]
}

@test "run_verification: handles mode: none correctly" {
  local metadata_file="$TEST_DIR/metadata.yaml"
  cat > "$metadata_file" << 'EOF'
name: test-image
verification:
  mode: none
  reason: "Test skip reason"
EOF

  run run_verification "test-image" "1.0.0" "$metadata_file"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Skipping verification" ]]
  [[ "$output" =~ "Test skip reason" ]]
}

@test "run_verification: returns error for invalid config" {
  local metadata_file="$TEST_DIR/metadata.yaml"
  cat > "$metadata_file" << 'EOF'
name: test-image
verification:
  mode: python-cli
  # Missing required 'module' field
EOF

  run run_verification "test-image" "1.0.0" "$metadata_file"
  [ "$status" -eq 2 ]
}

# ============================================================================
# python-cli config parsing tests
# ============================================================================

@test "parse_verification_config: parses python-cli with setup and teardown" {
  local metadata_file="$TEST_DIR/metadata.yaml"
  cat > "$metadata_file" << 'EOF'
name: test-image
verification:
  mode: python-cli
  module: my_module
  setup:
    - echo "setup1"
    - echo "setup2"
  teardown:
    - echo "cleanup"
  env:
    FOO: bar
    BAZ: qux
EOF

  run parse_verification_config "$metadata_file"
  [ "$status" -eq 0 ]

  local setup_count
  setup_count=$(echo "$output" | jq '.setup | length')
  [ "$setup_count" -eq 2 ]

  local teardown_count
  teardown_count=$(echo "$output" | jq '.teardown | length')
  [ "$teardown_count" -eq 1 ]

  local foo_val
  foo_val=$(echo "$output" | jq -r '.env.FOO')
  [ "$foo_val" = "bar" ]
}

# ============================================================================
# binary config parsing tests
# ============================================================================

@test "parse_verification_config: parses binary with args array" {
  local metadata_file="$TEST_DIR/metadata.yaml"
  cat > "$metadata_file" << 'EOF'
name: test-image
verification:
  mode: binary
  binary: /usr/local/bin/myapp
  args:
    - --version
    - --verbose
  expected_exit_code: 0
EOF

  run parse_verification_config "$metadata_file"
  [ "$status" -eq 0 ]

  local binary
  binary=$(echo "$output" | jq -r '.binary')
  [ "$binary" = "/usr/local/bin/myapp" ]

  local args_count
  args_count=$(echo "$output" | jq '.args | length')
  [ "$args_count" -eq 2 ]

  local expected_code
  expected_code=$(echo "$output" | jq -r '.expected_exit_code')
  [ "$expected_code" = "0" ]
}
