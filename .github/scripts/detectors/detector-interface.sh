#!/usr/bin/env bash
#
# Detector Interface Template
#
# This is a template/reference for implementing version detectors that conform to the
# standard detector interface (see spec/contracts/detector-interface.md).
#
# Copy this file to create a new detector: cp detector-interface.sh my-detector.sh
# Replace the placeholder functions with detector-specific logic.
#
# Interface Requirements:
# - Accept --config and --image-name arguments
# - Output JSON to stdout
# - Use standard exit codes: 0 (success), 1 (failure), 2 (fatal error)
# - Enforce 30-second timeout
# - Check cache before detection
# - Use standard error codes
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

# Detector name (override in specific detector implementations)
DETECTOR_NAME="detector-interface"

# ============================================================================
# Standard JSON Output Functions
# ============================================================================

# Output success result
#
# Arguments:
#   $1: Version string
#   $2: Detector name
#   $3: Cached (true/false)
#   $4: Source URL (optional)
#
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

# Output failure result
#
# Arguments:
#   $1: Error code
#   $2: Error message
#   $3: Detector name (optional)
#
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

# Parse detector configuration from metadata.yaml
#
# Validates YAML structure and required fields based on version_source type.
# This is a template function - override in specific detectors for detector-specific config.
#
# Arguments:
#   $1: Path to metadata.yaml
#
# Returns:
#   0 on success, 2 on config error
#
parse_detector_config() {
  local config_file="$1"

  if [[ ! -f "$config_file" ]]; then
    echo "ERROR: Config file not found: $config_file" >&2
    output_error "CONFIG_ERROR" "Config file not found: $config_file" "$DETECTOR_NAME"
    return 2
  fi

  # Validate YAML can be parsed
  if ! yq eval '.version_source' "$config_file" >/dev/null 2>&1; then
    echo "ERROR: Invalid YAML in config file: $config_file" >&2
    output_error "CONFIG_ERROR" "Invalid YAML in config file: $config_file" "$DETECTOR_NAME"
    return 2
  fi

  # Get version_source type
  local version_source_type
  version_source_type=$(yq eval '.version_source.type' "$config_file" 2>/dev/null)

  if [[ -z "$version_source_type" || "$version_source_type" == "null" ]]; then
    echo "ERROR: version_source.type not found in config" >&2
    output_error "CONFIG_ERROR" "version_source.type is required in config" "$DETECTOR_NAME"
    return 2
  fi

  # Validate required fields based on version_source type
  case "$version_source_type" in
    github-releases)
      local repo
      repo=$(yq eval '.version_source.repo' "$config_file" 2>/dev/null)
      if [[ -z "$repo" || "$repo" == "null" ]]; then
        echo "ERROR: version_source.repo is required for github-releases type" >&2
        output_error "CONFIG_ERROR" "version_source.repo is required for github-releases type" "$DETECTOR_NAME"
        return 2
      fi
      # Validate repo format (must be owner/repo)
      if [[ ! "$repo" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$ ]]; then
        echo "ERROR: version_source.repo format is invalid: $repo (expected: owner/repo)" >&2
        output_error "CONFIG_ERROR" "version_source.repo format is invalid: $repo (expected: owner/repo)" "$DETECTOR_NAME"
        return 2
      fi
      ;;
    *)
      # For other types, just check that type exists (already validated above)
      ;;
  esac

  if [[ "${DEBUG:-}" == "true" ]]; then
    echo "INFO: Parsed detector configuration from $config_file" >&2
  fi
  return 0
}

# ============================================================================
# Detection Logic
# ============================================================================

# Perform version detection
#
# This is a template function - override with detector-specific logic.
#
# Arguments:
#   $1: Path to metadata.yaml
#   $2: Image name
#
# Output:
#   Version string on success
#
# Returns:
#   0 on success, 1 on failure, 2 on config error
#
detect_version() {
  local config_file="$1"
  local image_name="$2"

  # Validate configuration
  # Note: parse_detector_config outputs error JSON to stdout on config errors
  parse_detector_config "$config_file" 2>/dev/null || return 2

  # Placeholder: Perform detection logic
  # This should be replaced with detector-specific implementation
  if [[ "${DEBUG:-}" == "true" ]]; then
    echo "ERROR: Detection logic not implemented (using template)" >&2
  fi

  # Template: Return version string to indicate detection worked (for testing)
  # Actual detectors should replace this with real detection logic
  echo "1.0.0-template"
  return 0
}

# ============================================================================
# Main Entry Point
# ============================================================================

# Parse command-line arguments
#
# Expected arguments:
#   --config <path-to-metadata.yaml>
#   --image-name <image-name>
#
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

# Main function
#
main() {
  # Parse arguments
  local args
  args=$(parse_arguments "$@") || {
    output_error "CONFIG_ERROR" "Invalid arguments: $*" "$DETECTOR_NAME"
    exit 2
  }

  read -r config_file image_name <<< "$args"

  # Only output INFO messages if DEBUG is enabled
  if [[ "${DEBUG:-}" == "true" ]]; then
    echo "INFO: Starting version detection for $image_name using $DETECTOR_NAME detector" >&2
  fi

  # Validate configuration first (even before checking cache)
  # This ensures config errors are caught regardless of cache status
  parse_detector_config "$config_file" >/dev/null 2>&1 || {
    exit_code=$?
    if [[ $exit_code -eq 2 ]]; then
      # Output the error JSON (which was already output by parse_detector_config)
      # Re-run to get the output
      parse_detector_config "$config_file" 2>/dev/null
      exit 2
    fi
  }

  # Check cache after config validation
  local cached_version
  if cached_version=$(get_cached_version "$image_name" 2>/dev/null); then
    if [[ "${DEBUG:-}" == "true" ]]; then
      echo "INFO: Using cached version for $image_name: $cached_version" >&2
    fi
    output_success "$cached_version" "$DETECTOR_NAME" true
    exit 0
  fi

  # Perform detection
  if [[ "${DEBUG:-}" == "true" ]]; then
    echo "INFO: Performing fresh detection for $image_name" >&2
  fi

  local version
  local exit_code

  # Call detect_version (timeout enforced at CI/CD level via workflow timeout)
  # Keep stderr separate from stdout (JSON output should be on stdout only)
  version=$(detect_version "$config_file" "$image_name") || {
    exit_code=$?
    if [[ $exit_code -eq 2 ]]; then
      # Fatal configuration error
      echo "$version"  # This contains the error JSON from detect_version
      exit 2
    else
      # Detection failed
      echo "$version"  # This contains the error JSON from detect_version
      exit 1
    fi
  }

  if [[ -z "$version" ]]; then
    if [[ "${DEBUG:-}" == "true" ]]; then
      echo "ERROR: Detection returned empty version" >&2
    fi
    output_error "PARSE_ERROR" "Detection returned empty version" "$DETECTOR_NAME"
    exit 1
  fi

  # Cache the result
  write_cache "$image_name" "$version" "$DETECTOR_NAME" "" 2>/dev/null

  # Output success
  output_success "$version" "$DETECTOR_NAME" false
  exit 0
}

# Run main function
main "$@"
