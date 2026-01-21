#!/bin/bash
# verification.sh - Container image verification library
#
# Provides functions to verify container images work correctly after build.
# Verification configuration is read from metadata.yaml.
#
# Supported verification modes:
#   - none: Skip verification (for images that can't be tested standalone)
#   - python-cli: Import module + run --help (Python CLI applications)
#   - binary: Execute binary with flag (Go/Rust binaries)
#   - command: Run custom commands (complex or unique verification)
#   - port: Start container, check port (network services)
#
# Usage:
#   source .github/scripts/lib/verification.sh
#   run_verification "hello-world" "1.0.0" "/path/to/metadata.yaml"
#
# Exit Codes:
#   0: Verification passed
#   1: Verification failed
#   2: Configuration error
#   3: Timeout

set -euo pipefail

# Source logging library if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/logging.sh" ]]; then
  source "${SCRIPT_DIR}/logging.sh"
fi

# Valid verification modes
readonly VALID_VERIFICATION_MODES=("none" "python-cli" "binary" "command" "port")

# Default timeout for container operations (seconds)
readonly DEFAULT_TIMEOUT=60
readonly DEFAULT_PORT_TIMEOUT=30

# parse_verification_config: Parse verification configuration from metadata.yaml
#
# Arguments:
#   METADATA_FILE: Path to metadata.yaml
#
# Outputs:
#   JSON object with verification configuration to stdout
#
# Returns:
#   0 on success
#   2 on configuration error
#
parse_verification_config() {
  local metadata_file="$1"

  if [[ ! -f "$metadata_file" ]]; then
    echo '{"error": "metadata file not found"}' >&2
    return 2
  fi

  # Extract verification section as JSON
  local config
  config=$(yq eval '.verification // {}' "$metadata_file" -o=json 2>/dev/null) || {
    echo '{"error": "failed to parse metadata.yaml"}' >&2
    return 2
  }

  echo "$config"
}

# get_verification_mode: Extract verification mode from config
#
# Arguments:
#   CONFIG_JSON: JSON verification configuration
#
# Outputs:
#   Mode string to stdout (defaults to empty if not set)
#
get_verification_mode() {
  local config="$1"
  echo "$config" | jq -r '.mode // ""'
}

# validate_verification_config: Validate verification configuration
#
# Arguments:
#   CONFIG_JSON: JSON verification configuration
#
# Returns:
#   0 if valid
#   2 if invalid configuration
#
# Outputs:
#   Error message to stderr on failure
#
validate_verification_config() {
  local config="$1"
  local mode

  mode=$(get_verification_mode "$config")

  # Empty mode is allowed (backwards compatible - warning will be logged)
  if [[ -z "$mode" ]]; then
    return 0
  fi

  # Check mode is valid
  local valid=false
  for valid_mode in "${VALID_VERIFICATION_MODES[@]}"; do
    if [[ "$mode" == "$valid_mode" ]]; then
      valid=true
      break
    fi
  done

  if [[ "$valid" != "true" ]]; then
    echo "ERROR: Invalid verification mode: $mode" >&2
    echo "Valid modes: ${VALID_VERIFICATION_MODES[*]}" >&2
    return 2
  fi

  # Mode-specific validation
  case "$mode" in
    python-cli)
      local module
      module=$(echo "$config" | jq -r '.module // ""')
      if [[ -z "$module" ]]; then
        echo "ERROR: python-cli mode requires 'module' field" >&2
        return 2
      fi
      ;;
    binary)
      local binary
      binary=$(echo "$config" | jq -r '.binary // ""')
      if [[ -z "$binary" ]]; then
        echo "ERROR: binary mode requires 'binary' field" >&2
        return 2
      fi
      ;;
    command)
      local commands
      commands=$(echo "$config" | jq -r '.commands // []')
      if [[ "$commands" == "[]" ]] || [[ -z "$commands" ]]; then
        echo "ERROR: command mode requires 'commands' array" >&2
        return 2
      fi
      ;;
    port)
      local port
      port=$(echo "$config" | jq -r '.port // ""')
      if [[ -z "$port" ]]; then
        echo "ERROR: port mode requires 'port' field" >&2
        return 2
      fi
      if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        echo "ERROR: port must be a valid port number (1-65535)" >&2
        return 2
      fi
      ;;
    none)
      # No additional validation needed
      ;;
  esac

  return 0
}

# run_in_container: Execute a command in a container
#
# Arguments:
#   IMAGE: Image name:tag to run
#   COMMAND: Command to execute
#   [TIMEOUT]: Timeout in seconds (default: 60)
#   [ENV_VARS]: JSON object of environment variables (optional)
#
# Returns:
#   Exit code from container command
#
# Outputs:
#   Command output to stdout
#   Errors to stderr
#
run_in_container() {
  local image="$1"
  local command="$2"
  local timeout="${3:-$DEFAULT_TIMEOUT}"
  local env_vars="${4:-{}}"

  local docker_args=("--rm" "--entrypoint" "")

  # Add environment variables
  while IFS= read -r env_line; do
    if [[ -n "$env_line" ]]; then
      docker_args+=("-e" "$env_line")
    fi
  done < <(echo "$env_vars" | jq -r 'to_entries | .[] | "\(.key)=\(.value)"' 2>/dev/null || true)

  # Run container with timeout, bypassing entrypoint to run verification commands directly
  timeout "$timeout" docker run "${docker_args[@]}" "$image" sh -c "$command" 2>&1
}

# run_container_background: Start a container in the background
#
# Arguments:
#   IMAGE: Image name:tag to run
#   [PORT]: Port to expose (optional)
#   [ENV_VARS]: JSON object of environment variables (optional)
#
# Outputs:
#   Container ID to stdout
#
# Returns:
#   0 on success, 1 on failure
#
run_container_background() {
  local image="$1"
  local port="${2:-}"
  local env_vars="${3:-{}}"

  local docker_args=("--rm" "-d")

  # Add port mapping if specified
  if [[ -n "$port" ]]; then
    docker_args+=("-p" "$port:$port")
  fi

  # Add environment variables
  while IFS= read -r env_line; do
    if [[ -n "$env_line" ]]; then
      docker_args+=("-e" "$env_line")
    fi
  done < <(echo "$env_vars" | jq -r 'to_entries | .[] | "\(.key)=\(.value)"' 2>/dev/null || true)

  docker run "${docker_args[@]}" "$image"
}

# wait_for_port: Wait for a port to become available
#
# Arguments:
#   HOST: Host to check
#   PORT: Port number
#   TIMEOUT: Timeout in seconds
#
# Returns:
#   0 if port becomes available
#   3 if timeout
#
wait_for_port() {
  local host="$1"
  local port="$2"
  local timeout="$3"

  local start_time
  start_time=$(date +%s)
  local end_time=$((start_time + timeout))

  while [[ $(date +%s) -lt $end_time ]]; do
    if nc -z "$host" "$port" 2>/dev/null; then
      return 0
    fi
    sleep 1
  done

  return 3
}

# check_http_health: Check HTTP health endpoint
#
# Arguments:
#   URL: Full URL to check
#   EXPECTED_CODE: Expected HTTP status code (default: 200)
#
# Returns:
#   0 if health check passes
#   1 if health check fails
#
check_http_health() {
  local url="$1"
  local expected_code="${2:-200}"

  local status_code
  status_code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null) || return 1

  if [[ "$status_code" == "$expected_code" ]]; then
    return 0
  fi

  echo "Health check failed: expected $expected_code, got $status_code" >&2
  return 1
}

# check_stdout_contains: Verify command output contains expected string
#
# Arguments:
#   OUTPUT: Command output to check
#   EXPECTED: String that should be present
#
# Returns:
#   0 if output contains expected string
#   1 if not found
#
check_stdout_contains() {
  local output="$1"
  local expected="$2"

  if [[ "$output" == *"$expected"* ]]; then
    return 0
  fi

  return 1
}

# verify_python_cli: Verify Python CLI application
#
# Arguments:
#   IMAGE: Docker image name:tag
#   CONFIG: JSON verification configuration
#
# Returns:
#   0 on success
#   1 on verification failure
#
verify_python_cli() {
  local image="$1"
  local config="$2"

  local module
  local help_command
  local setup_commands
  local teardown_commands
  local env_vars

  module=$(echo "$config" | jq -r '.module')
  help_command=$(echo "$config" | jq -r '.help_command // "python3 -m '"$module"' --help"')
  setup_commands=$(echo "$config" | jq -r '.setup // []')
  teardown_commands=$(echo "$config" | jq -r '.teardown // []')
  env_vars=$(echo "$config" | jq -r '.env // {}')

  echo "[VERIFY] Python CLI verification for module: $module"

  # Build combined command with setup, verification, and teardown
  local full_command=""

  # Add setup commands
  while IFS= read -r setup_cmd; do
    if [[ -n "$setup_cmd" ]] && [[ "$setup_cmd" != "null" ]]; then
      full_command+="$setup_cmd; "
    fi
  done < <(echo "$setup_commands" | jq -r '.[]' 2>/dev/null || true)

  # Add import check
  full_command+="python3 -c \"import $module\" && "

  # Add help command
  full_command+="$help_command > /dev/null"

  # Add teardown commands
  while IFS= read -r teardown_cmd; do
    if [[ -n "$teardown_cmd" ]] && [[ "$teardown_cmd" != "null" ]]; then
      full_command+="; $teardown_cmd"
    fi
  done < <(echo "$teardown_commands" | jq -r '.[]' 2>/dev/null || true)

  echo "[VERIFY] Running: $full_command"

  local output
  local exit_code=0
  output=$(run_in_container "$image" "$full_command" "$DEFAULT_TIMEOUT" "$env_vars") || exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    echo "[VERIFY] Python CLI verification passed"
    return 0
  else
    echo "[VERIFY] Python CLI verification failed with exit code $exit_code"
    echo "[VERIFY] Output: $output"
    return 1
  fi
}

# verify_binary: Verify binary executable
#
# Arguments:
#   IMAGE: Docker image name:tag
#   CONFIG: JSON verification configuration
#
# Returns:
#   0 on success
#   1 on verification failure
#
verify_binary() {
  local image="$1"
  local config="$2"

  local binary
  local args
  local expected_exit_code

  binary=$(echo "$config" | jq -r '.binary')
  args=$(echo "$config" | jq -r '.args // ["--version"] | join(" ")')
  expected_exit_code=$(echo "$config" | jq -r '.expected_exit_code // 0')

  echo "[VERIFY] Binary verification for: $binary $args"

  local output
  local exit_code=0
  output=$(run_in_container "$image" "$binary $args" "$DEFAULT_TIMEOUT") || exit_code=$?

  if [[ "$exit_code" == "$expected_exit_code" ]]; then
    echo "[VERIFY] Binary verification passed"
    return 0
  else
    echo "[VERIFY] Binary verification failed: expected exit code $expected_exit_code, got $exit_code"
    echo "[VERIFY] Output: $output"
    return 1
  fi
}

# verify_command: Verify using custom commands
#
# Arguments:
#   IMAGE: Docker image name:tag
#   CONFIG: JSON verification configuration
#
# Returns:
#   0 on success
#   1 on verification failure
#
verify_command() {
  local image="$1"
  local config="$2"

  local commands
  commands=$(echo "$config" | jq -c '.commands // []')

  local total_commands
  total_commands=$(echo "$commands" | jq 'length')

  echo "[VERIFY] Running $total_commands custom verification command(s)"

  local i=0
  while [[ $i -lt $total_commands ]]; do
    local cmd_config
    local cmd_name
    local cmd_run
    local stdout_contains

    cmd_config=$(echo "$commands" | jq -c ".[$i]")
    cmd_name=$(echo "$cmd_config" | jq -r '.name // "Command '"$((i+1))"'"')
    cmd_run=$(echo "$cmd_config" | jq -r '.run')
    stdout_contains=$(echo "$cmd_config" | jq -r '.stdout_contains // ""')

    echo "[VERIFY] Running: $cmd_name"
    echo "[VERIFY]   Command: $cmd_run"

    local output
    local exit_code=0
    output=$(run_in_container "$image" "$cmd_run" "$DEFAULT_TIMEOUT") || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
      echo "[VERIFY] Command '$cmd_name' failed with exit code $exit_code"
      echo "[VERIFY] Output: $output"
      return 1
    fi

    # Check stdout_contains if specified
    if [[ -n "$stdout_contains" ]]; then
      if ! check_stdout_contains "$output" "$stdout_contains"; then
        echo "[VERIFY] Command '$cmd_name' output does not contain: $stdout_contains"
        echo "[VERIFY] Output: $output"
        return 1
      fi
      echo "[VERIFY]   Output contains: $stdout_contains"
    fi

    echo "[VERIFY] Command '$cmd_name' passed"
    i=$((i + 1))
  done

  echo "[VERIFY] All custom commands passed"
  return 0
}

# verify_port: Verify container starts and port becomes available
#
# Arguments:
#   IMAGE: Docker image name:tag
#   CONFIG: JSON verification configuration
#
# Returns:
#   0 on success
#   1 on verification failure
#   3 on timeout
#
verify_port() {
  local image="$1"
  local config="$2"

  local port
  local startup_timeout
  local health_path
  local env_vars

  port=$(echo "$config" | jq -r '.port')
  startup_timeout=$(echo "$config" | jq -r '.startup_timeout // '"$DEFAULT_PORT_TIMEOUT"'')
  health_path=$(echo "$config" | jq -r '.health_path // ""')
  env_vars=$(echo "$config" | jq -r '.env // {}')

  echo "[VERIFY] Port verification for port: $port"
  echo "[VERIFY] Startup timeout: ${startup_timeout}s"

  # Start container in background
  local container_id
  container_id=$(run_container_background "$image" "$port" "$env_vars") || {
    echo "[VERIFY] Failed to start container"
    return 1
  }

  echo "[VERIFY] Started container: $container_id"

  # Wait for port to become available
  local port_result=0
  if ! wait_for_port "localhost" "$port" "$startup_timeout"; then
    echo "[VERIFY] Timeout waiting for port $port"
    docker stop "$container_id" >/dev/null 2>&1 || true
    return 3
  fi

  echo "[VERIFY] Port $port is available"

  # Check HTTP health endpoint if specified
  if [[ -n "$health_path" ]]; then
    local health_url="http://localhost:$port$health_path"
    echo "[VERIFY] Checking health endpoint: $health_url"

    if ! check_http_health "$health_url"; then
      echo "[VERIFY] Health check failed"
      docker stop "$container_id" >/dev/null 2>&1 || true
      return 1
    fi

    echo "[VERIFY] Health check passed"
  fi

  # Cleanup
  docker stop "$container_id" >/dev/null 2>&1 || true

  echo "[VERIFY] Port verification passed"
  return 0
}

# run_verification: Main entry point for verification
#
# Arguments:
#   IMAGE_NAME: Name of the image (used for logging)
#   IMAGE_TAG: Tag of the image
#   METADATA_FILE: Path to metadata.yaml
#   [PLATFORM]: Platform to verify (e.g., linux/amd64) - optional
#
# Returns:
#   0: Verification passed
#   1: Verification failed
#   2: Configuration error
#   3: Timeout
#
run_verification() {
  local image_name="$1"
  local image_tag="$2"
  local metadata_file="$3"
  local platform="${4:-}"

  # Build full image reference
  # If image_name already contains a digest (@sha256:), use it as-is
  # Docker references must be EITHER image:tag OR image@sha256:digest, NOT both
  local full_image
  if [[ "$image_name" == *"@sha256:"* ]]; then
    full_image="$image_name"
  else
    full_image="$image_name:$image_tag"
  fi

  echo "[VERIFY] ════════════════════════════════════════════════════════════"
  echo "[VERIFY] Starting verification for: $full_image"
  echo "[VERIFY] Metadata file: $metadata_file"
  if [[ -n "$platform" ]]; then
    echo "[VERIFY] Platform: $platform"
  fi
  echo "[VERIFY] ════════════════════════════════════════════════════════════"

  # Parse configuration
  local config
  config=$(parse_verification_config "$metadata_file") || return 2

  # Validate configuration
  if ! validate_verification_config "$config"; then
    return 2
  fi

  # Get verification mode
  local mode
  mode=$(get_verification_mode "$config")

  # Handle missing verification config (backwards compatible)
  if [[ -z "$mode" ]]; then
    echo "[VERIFY] WARNING: No verification config in metadata.yaml"
    echo "[VERIFY] Skipping verification (backwards compatible mode)"
    echo "[VERIFY] Consider adding verification config to metadata.yaml"
    return 0
  fi

  echo "[VERIFY] Verification mode: $mode"

  # Execute verification based on mode
  case "$mode" in
    none)
      local reason
      reason=$(echo "$config" | jq -r '.reason // "No reason provided"')
      echo "[VERIFY] Skipping verification: $reason"
      return 0
      ;;
    python-cli)
      verify_python_cli "$full_image" "$config"
      return $?
      ;;
    binary)
      verify_binary "$full_image" "$config"
      return $?
      ;;
    command)
      verify_command "$full_image" "$config"
      return $?
      ;;
    port)
      verify_port "$full_image" "$config"
      return $?
      ;;
    *)
      echo "[VERIFY] ERROR: Unknown verification mode: $mode"
      return 2
      ;;
  esac
}

# output_json_result: Output verification result as JSON
#
# Arguments:
#   IMAGE_NAME: Name of the image
#   IMAGE_TAG: Tag of the image
#   MODE: Verification mode
#   STATUS: passed, failed, skipped, error
#   MESSAGE: Result message
#   EXIT_CODE: Exit code
#
output_json_result() {
  local image_name="$1"
  local image_tag="$2"
  local mode="$3"
  local status="$4"
  local message="$5"
  local exit_code="$6"

  jq -n \
    --arg image "$image_name" \
    --arg tag "$image_tag" \
    --arg mode "$mode" \
    --arg status "$status" \
    --arg message "$message" \
    --argjson exit_code "$exit_code" \
    '{
      image: $image,
      tag: $tag,
      verification: {
        mode: $mode,
        status: $status,
        message: $message,
        exit_code: $exit_code
      }
    }'
}

export -f parse_verification_config
export -f get_verification_mode
export -f validate_verification_config
export -f run_in_container
export -f run_container_background
export -f wait_for_port
export -f check_http_health
export -f check_stdout_contains
export -f verify_python_cli
export -f verify_binary
export -f verify_command
export -f verify_port
export -f run_verification
export -f output_json_result
