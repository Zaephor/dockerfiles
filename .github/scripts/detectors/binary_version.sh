#!/usr/bin/env bash
#
# Binary Version Detector
#
# Detects versions by executing a binary inside a Docker container and parsing
# the --version output using a configurable regex pattern.
#
# Usage:
#   ./binary-version.sh --config /path/to/metadata.yaml --image-name image-name
#
# Configuration (metadata.yaml):
#   version_source:
#     type: binary
#     binary_path: /usr/local/bin/tool  # Required: path to binary in container
#     version_regex: 'version ([0-9.]+)'  # Required: regex pattern to extract version
#     version_flags: '--version'  # Optional: flags to pass to binary (default: --version)
#

set -euo pipefail

# Script directory (for sourcing libraries)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Source libraries
source "${LIB_DIR}/cache.sh" || {
  echo "ERROR: Failed to source cache library" >&2
  exit 2
}

source "${LIB_DIR}/version-parser.sh" || {
  echo "ERROR: Failed to source version parser library" >&2
  exit 2
}

readonly DETECTOR_NAME="binary-version"

# ============================================================================
# Standard JSON Output Functions
# ============================================================================

output_success() {
  local version="$1"
  local detector="$2"
  local cached="${3:-false}"
  local source_url="${4:-}"

  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  cat <<EOF
{
  "version": "${version}",
  "status": "success",
  "detector": "${detector}",
  "cached": ${cached},
  "metadata": {
    "source_url": "${source_url}",
    "detected_at": "${timestamp}"
  }
}
EOF
}

output_error() {
  local error_code="$1"
  local error_message="$2"
  local detector="${3:-unknown}"

  cat <<EOF
{
  "version": null,
  "status": "failure",
  "detector": "${detector}",
  "error": "${error_message}",
  "error_code": "${error_code}"
}
EOF
}

# ============================================================================
# Configuration Parsing
# ============================================================================

# Parse binary detector configuration from metadata.yaml
#
# Arguments:
#   $1: Path to metadata.yaml
#   $2: Image directory (for building container)
#
# Output:
#   binary_path, version_regex, version_flags (one per line)
#
# Returns:
#   0 on success, 2 on config error
#
parse_binary_config() {
  local config_file="$1"
  local image_dir="${2:-.}"

  if [[ ! -f "$config_file" ]]; then
    output_error "CONFIG_ERROR" "Config file not found: $config_file" "$DETECTOR_NAME"
    return 2
  fi

  # Extract binary_path
  local binary_path
  binary_path=$(yq eval '.version_source.binary_path' "$config_file" 2>/dev/null) || {
    output_error "CONFIG_ERROR" "Failed to parse version_source from $config_file" "$DETECTOR_NAME"
    return 2
  }

  if [[ -z "$binary_path" || "$binary_path" == "null" ]]; then
    output_error "CONFIG_ERROR" "Missing required field: version_source.binary_path" "$DETECTOR_NAME"
    return 2
  fi

  # Extract version_regex
  local version_regex
  version_regex=$(yq eval '.version_source.version_regex' "$config_file" 2>/dev/null) || {
    output_error "CONFIG_ERROR" "Failed to parse version_regex from $config_file" "$DETECTOR_NAME"
    return 2
  }

  if [[ -z "$version_regex" || "$version_regex" == "null" ]]; then
    output_error "CONFIG_ERROR" "Missing required field: version_source.version_regex" "$DETECTOR_NAME"
    return 2
  fi

  # Extract optional version_flags (default: --version)
  local version_flags
  version_flags=$(yq eval '.version_source.version_flags' "$config_file" 2>/dev/null || echo "--version")
  [[ "$version_flags" == "null" ]] && version_flags="--version"

  # Output parsed values
  echo "$binary_path"
  echo "$version_regex"
  echo "$version_flags"

  return 0
}

# ============================================================================
# Container Execution
# ============================================================================

# Build a temporary container from image Dockerfile
#
# Arguments:
#   $1: Image directory (contains Dockerfile)
#   $2: Image name
#
# Output:
#   Temporary image name (e.g., temp-version-check:image-name)
#
# Returns:
#   0 on success, 1 on failure
#
build_temp_container() {
  local image_dir="$1"
  local image_name="$2"

  local temp_image="temp-version-check:${image_name}"

  if [[ "${DEBUG:-}" == "true" ]]; then
    echo "INFO: Building temporary container: $temp_image" >&2
  fi

  # Build container with timeout
  if timeout 120s docker build -t "$temp_image" "$image_dir" >/dev/null 2>&1; then
    echo "$temp_image"
    return 0
  else
    echo "ERROR: Failed to build temporary container" >&2
    return 1
  fi
}

# Execute binary inside container and capture output
#
# Arguments:
#   $1: Container image name
#   $2: Binary path
#   $3: Version flags
#
# Output:
#   Binary output (stdout + stderr combined)
#
# Returns:
#   0 on success, 1 on failure
#
execute_binary_in_container() {
  local container_image="$1"
  local binary_path="$2"
  local version_flags="$3"

  if [[ "${DEBUG:-}" == "true" ]]; then
    echo "INFO: Executing binary in container: $binary_path $version_flags" >&2
  fi

  # Execute binary with timeout, capture both stdout and stderr
  timeout 30s docker run --rm "$container_image" $binary_path $version_flags 2>&1 || {
    local exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
      return 1  # Timeout
    fi
    # Non-zero exit is OK, return output anyway
    return 0
  }

  return 0
}

# ============================================================================
# Detection Logic
# ============================================================================

# Perform version detection from binary execution
#
# Arguments:
#   $1: Path to metadata.yaml
#   $2: Image name
#
# Output:
#   Version string on success, JSON error on failure
#
# Returns:
#   0 on success, 1 on failure, 2 on config error
#
detect_version() {
  local config_file="$1"
  local image_name="$2"

  # Determine image directory (parent directory of config file)
  local image_dir
  image_dir=$(dirname "$config_file")

  # Parse configuration
  local config_output
  config_output=$(parse_binary_config "$config_file" "$image_dir") || return 2

  read -r binary_path version_regex version_flags <<< "$config_output"

  if [[ "${DEBUG:-}" == "true" ]]; then
    echo "INFO: Detecting binary version: $binary_path" >&2
  fi

  # Build temporary container from image Dockerfile
  local container_image
  container_image=$(build_temp_container "$image_dir" "$image_name") || {
    output_error "NETWORK_ERROR" "Failed to build temporary container for binary execution" "$DETECTOR_NAME"
    return 1
  }

  if [[ "${DEBUG:-}" == "true" ]]; then
    echo "INFO: Built temporary container: $container_image" >&2
  fi

  # Execute binary in container
  local binary_output
  binary_output=$(execute_binary_in_container "$container_image" "$binary_path" "$version_flags") || {
    # Clean up temporary container
    docker rmi -f "$container_image" >/dev/null 2>&1 || true
    output_error "TIMEOUT" "Binary execution timed out after 30 seconds" "$DETECTOR_NAME"
    return 1
  }

  # Clean up temporary container
  docker rmi -f "$container_image" >/dev/null 2>&1 || true

  if [[ -z "$binary_output" ]]; then
    output_error "PARSE_ERROR" "Binary produced no output" "$DETECTOR_NAME"
    return 1
  fi

  # Extract version using regex
  local version
  if [[ "$binary_output" =~ $version_regex ]]; then
    version="${BASH_REMATCH[1]}"
  else
    echo "ERROR: Failed to extract version from binary output using regex: $version_regex" >&2
    echo "DEBUG: Binary output: $binary_output" >&2
    output_error "PARSE_ERROR" "Failed to extract version from binary output using regex pattern" "$DETECTOR_NAME"
    return 1
  fi

  if [[ -z "$version" ]]; then
    output_error "PARSE_ERROR" "Regex match produced empty version" "$DETECTOR_NAME"
    return 1
  fi

  # Generate source URL
  local source_url="binary:${binary_path}"

  echo "$version"
  echo "$source_url"
  return 0
}

# ============================================================================
# Main Entry Point
# ============================================================================

# Parse command-line arguments
parse_arguments() {
  local config_file=""
  local image_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        config_file="$2"
        shift 2
        ;;
      --image-name)
        image_name="$2"
        shift 2
        ;;
      *)
        echo "ERROR: Unknown argument: $1" >&2
        return 1
        ;;
    esac
  done

  if [[ -z "$config_file" || -z "$image_name" ]]; then
    echo "ERROR: Missing required arguments: --config and --image-name" >&2
    return 1
  fi

  echo "$config_file" "$image_name"
  return 0
}

main() {
  # Parse arguments
  local args
  args=$(parse_arguments "$@") || {
    output_error "CONFIG_ERROR" "Invalid arguments: $*" "$DETECTOR_NAME"
    exit 2
  }

  read -r config_file image_name <<< "$args"

  if [[ "${DEBUG:-}" == "true" ]]; then
    echo "INFO: Binary version detector starting for image: $image_name" >&2
  fi

  # Check cache first
  local cached_version
  if cached_version=$(get_cached_version "$image_name" 2>/dev/null); then
    if [[ "${DEBUG:-}" == "true" ]]; then
      echo "INFO: Using cached version for $image_name: $cached_version" >&2
    fi
    output_success "$cached_version" "$DETECTOR_NAME" true
    exit 0
  fi

  # Perform detection with timeout
  if [[ "${DEBUG:-}" == "true" ]]; then
    echo "INFO: Performing fresh detection for $image_name" >&2
  fi

  local version
  local source_url
  local output
  local exit_code

  # Invoke detection (timeout enforced by CI/CD environment, not shell wrapper)
  # Shell functions cannot be wrapped with 'timeout' command as timeout cannot
  # execute bash functions directly. CI/CD environments enforce timeouts at job level.
  # Note: Do NOT redirect stderr here - we want INFO logs on stderr, JSON output on stdout
  output=$(detect_version "$config_file" "$image_name") || {
    exit_code=$?
    if [[ $exit_code -eq 2 ]]; then
      # Fatal configuration error
      echo "$output"
      exit 2
    else
      # Detection failed
      echo "$output"
      exit 1
    fi
  }

  # Parse output (version and source URL)
  read -r version source_url <<< "$output"

  if [[ -z "$version" ]]; then
    echo "ERROR: Detection returned empty version" >&2
    output_error "PARSE_ERROR" "Detection returned empty version" "$DETECTOR_NAME"
    exit 1
  fi

  # Cache the result
  write_cache "$image_name" "$version" "$DETECTOR_NAME" "$source_url"

  # Output success
  output_success "$version" "$DETECTOR_NAME" false "$source_url"
  exit 0
}

# Run main function
main "$@"
