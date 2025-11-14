#!/usr/bin/env bash
#
# Version Detection Orchestrator
#
# Orchestrates version detection using multiple detector types with fallback logic.
# Detectors are invoked in sequence from metadata.yaml configuration.
# Stops on first success, reports failure if all detectors fail.
#
# Usage:
#   ./version-detection.sh --config /path/to/metadata.yaml --image-name image-name
#
# Output:
#   JSON object with detection result or error
#
# Exit Codes:
#   0 = Success (version detected)
#   1 = Failure (all detectors failed)
#   2 = Fatal error (configuration error)
#

set -euo pipefail

# Script directory (for sourcing libraries and detectors)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
DETECTORS_DIR="${SCRIPT_DIR}/detectors"

# Source libraries
source "${LIB_DIR}/cache.sh" || {
  echo "ERROR: Failed to source cache library" >&2
  exit 2
}

# ============================================================================
# Configuration Parsing
# ============================================================================

# Parse command-line arguments
#
# Arguments:
#   All command-line arguments
#
# Output:
#   config_file and image_name (separated by newline)
#
# Returns:
#   0 on success, 1 on invalid arguments
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

# Parse detector configuration from metadata.yaml
#
# Supports both single detector and array of detectors:
#   version_source:
#     type: github-releases
#     repo: owner/project
#
# OR:
#
#   version_source:
#     - type: github-releases
#       repo: owner/project
#     - type: binary
#       binary_path: /usr/bin/tool
#
# Arguments:
#   $1: Path to metadata.yaml
#
# Output:
#   YAML strings for each detector config (one per line)
#
# Returns:
#   0 on success, 1 on config error
#
parse_detectors_from_config() {
  local config_file="$1"

  if [[ ! -f "$config_file" ]]; then
    echo "ERROR: Config file not found: $config_file" >&2
    return 1
  fi

  # Check if version_source exists
  local version_source
  version_source=$(yq eval '.version_source' "$config_file" 2>/dev/null) || {
    echo "ERROR: Failed to parse version_source from $config_file" >&2
    return 1
  }

  if [[ -z "$version_source" || "$version_source" == "null" ]]; then
    echo "ERROR: version_source not found in $config_file" >&2
    return 1
  fi

  # Determine if version_source is array or single object by checking type
  local version_source_type
  version_source_type=$(yq eval '.version_source | type' "$config_file" 2>/dev/null) || {
    echo "ERROR: Failed to determine version_source type from $config_file" >&2
    return 1
  }

  if [[ "$version_source_type" == "!!seq" ]]; then
    # Array syntax
    echo "INFO: version_source is array (multiple detectors)" >&2

    # Use yq to convert to JSON then jq to extract array elements (one per line)
    # Each detector is output as a single JSON line for reliable parsing
    yq eval '.version_source' "$config_file" -o json 2>/dev/null | jq -c '.[]' 2>/dev/null || {
      echo "ERROR: Failed to parse version_source array from $config_file" >&2
      return 1
    }
  else
    # Single object syntax (backward compatible)
    echo "INFO: version_source is single object (fallback logic not used)" >&2
    # Convert to JSON for consistent parsing (compact, single line)
    yq eval '.version_source' "$config_file" -o json -I=0 2>/dev/null || {
      echo "ERROR: Failed to convert version_source to JSON from $config_file" >&2
      return 1
    }
  fi

  return 0
}

# Extract detector type from a detector YAML block
#
# Arguments:
#   $1: YAML string representing detector config
#
# Output:
#   Detector type name
#
# Returns:
#   0 on success, 1 if type not found
#
get_detector_type() {
  local detector_config="$1"

  local detector_type
  # Input may be JSON or YAML, jq handles both
  detector_type=$(echo "$detector_config" | jq -r '.type' 2>/dev/null) || {
    # Fallback to yq if jq fails
    detector_type=$(echo "$detector_config" | yq eval '.type' - 2>/dev/null) || return 1
  }

  if [[ -z "$detector_type" || "$detector_type" == "null" ]]; then
    return 1
  fi

  echo "$detector_type"
  return 0
}

# ============================================================================
# Detector Invocation
# ============================================================================

# Find and invoke the correct detector script
#
# Arguments:
#   $1: Detector type (github-releases, binary, docker-tags, http-api)
#   $2: Path to config file (or JSON detector config string if $4 is "json")
#   $3: Image name
#   $4: Optional - "json" if $2 is JSON config instead of file path
#
# Output:
#   JSON result from detector
#
# Returns:
#   0 = Success (version detected)
#   1 = Failure (detection failed, try next detector)
#   2 = Fatal error (don't try other detectors)
#
invoke_detector() {
  local detector_type="$1"
  local config_input="$2"
  local image_name="$3"
  local input_format="${4:-file}"  # "file" or "json"

  local detector_script="${DETECTORS_DIR}/${detector_type}.sh"

  if [[ ! -f "$detector_script" ]]; then
    echo "ERROR: Detector script not found: $detector_script" >&2
    return 2
  fi

  if [[ ! -x "$detector_script" ]]; then
    echo "ERROR: Detector script not executable: $detector_script" >&2
    return 2
  fi

  # If input is JSON detector config, wrap it in a temporary YAML file
  local config_file="$config_input"
  local temp_config=""

  if [[ "$input_format" == "json" ]]; then
    # Create temporary config file wrapping the detector config
    temp_config=$(mktemp) || {
      echo "ERROR: Failed to create temporary config file" >&2
      return 2
    }

    # Wrap JSON detector config under version_source in YAML format
    echo "version_source: $(echo "$config_input" | jq -c '.')" > "$temp_config"
    config_file="$temp_config"
  fi

  echo "INFO: Invoking detector: $detector_type for image: $image_name" >&2

  # Invoke detector and capture output
  local output
  local exit_code

  output=$("$detector_script" --config "$config_file" --image-name "$image_name") || {
    exit_code=$?
    echo "$output"
    # Clean up temp file if created
    [[ -n "$temp_config" && -f "$temp_config" ]] && rm -f "$temp_config"
    return $exit_code
  }

  # Clean up temp file if created
  [[ -n "$temp_config" && -f "$temp_config" ]] && rm -f "$temp_config"

  echo "$output"
  return 0
}

# ============================================================================
# Fallback Logic and Orchestration
# ============================================================================

# Run detection with fallback logic
#
# Tries each detector in sequence, stops on first success
#
# Arguments:
#   $1: Path to config file
#   $2: Image name
#
# Output:
#   JSON result from successful detector or aggregated error
#
# Returns:
#   0 = Success (version detected by some detector)
#   1 = Failure (all detectors failed)
#   2 = Fatal error (configuration error)
#
run_detection_with_fallback() {
  local config_file="$1"
  local image_name="$2"

  # Parse detectors from config
  local detectors
  detectors=$(parse_detectors_from_config "$config_file") || return 2

  # Convert detectors string to array
  local detector_array=()
  while IFS= read -r detector_config; do
    if [[ -n "$detector_config" ]]; then
      detector_array+=("$detector_config")
    fi
  done <<< "$detectors"

  if [[ ${#detector_array[@]} -eq 0 ]]; then
    echo "ERROR: No detectors found in configuration" >&2
    return 2
  fi

  echo "INFO: Attempting detection with ${#detector_array[@]} detector(s)" >&2

  # Validate all detector types exist before attempting detection
  for detector_config in "${detector_array[@]}"; do
    # Skip empty configs
    if [[ -z "$detector_config" ]]; then
      continue
    fi

    # Extract detector type
    local detector_type
    detector_type=$(get_detector_type "$detector_config") || {
      echo "ERROR: Failed to extract detector type from config" >&2
      return 2
    }

    # Validate detector script exists
    if [[ ! -f "${DETECTORS_DIR}/${detector_type}.sh" ]]; then
      echo "ERROR: Unknown detector type: ${detector_type}" >&2
      cat <<EOF
{
  "version": null,
  "status": "failure",
  "detector": "orchestrator",
  "error": "Unknown detector type: ${detector_type}",
  "error_code": "CONFIG_ERROR"
}
EOF
      return 2
    fi
  done

  # Try each detector in order
  local detector_index=0
  local last_error_output=""

  for detector_config in "${detector_array[@]}"; do
    detector_index=$((detector_index + 1))

    # Skip empty configs
    if [[ -z "$detector_config" ]]; then
      continue
    fi

    # Extract detector type (already validated above)
    local detector_type
    detector_type=$(get_detector_type "$detector_config") || {
      echo "ERROR: Failed to extract detector type from config" >&2
      continue
    }

    echo "INFO: Detector $detector_index/${#detector_array[@]}: $detector_type" >&2

    # Invoke detector
    # Determine if detector_config is JSON (from array) or YAML (from single object)
    local config_format="file"
    if [[ "$detector_config" =~ ^\{ ]]; then
      # JSON format (from array parsing)
      config_format="json"
    fi

    local result
    local exit_code

    result=$(invoke_detector "$detector_type" "$detector_config" "$image_name" "$config_format") || {
      exit_code=$?

      if [[ $exit_code -eq 2 ]]; then
        # Fatal error - don't try other detectors
        echo "ERROR: Fatal error from detector $detector_type (exit code 2)" >&2
        echo "$result"
        return 2
      fi

      # Failure - save and try next detector
      echo "WARN: Detector $detector_type failed (exit code 1)" >&2
      last_error_output="$result"
      continue
    }

    # Check if result is successful
    local status
    status=$(echo "$result" | jq -r '.status' 2>/dev/null) || {
      echo "ERROR: Failed to parse detector output as JSON" >&2
      last_error_output="$result"
      continue
    }

    if [[ "$status" == "success" ]]; then
      echo "INFO: Version detected by $detector_type" >&2
      echo "$result"
      return 0
    else
      # Detector returned failure (status: failure)
      echo "WARN: Detector $detector_type returned failure status" >&2
      last_error_output="$result"
      continue
    fi
  done

  # All detectors failed
  echo "ERROR: All detectors failed for image $image_name" >&2

  if [[ -n "$last_error_output" ]]; then
    # Output last error from detectors
    echo "$last_error_output"
  else
    # Generic error if no detector output available
    cat <<EOF
{
  "version": null,
  "status": "failure",
  "detector": "orchestrator",
  "error": "All detectors failed",
  "error_code": "ALL_DETECTORS_FAILED"
}
EOF
  fi

  return 1
}

# ============================================================================
# Main Entry Point
# ============================================================================

main() {
  # Parse command-line arguments
  local args
  args=$(parse_arguments "$@") || {
    cat <<EOF
{
  "version": null,
  "status": "failure",
  "detector": "orchestrator",
  "error": "Invalid arguments",
  "error_code": "CONFIG_ERROR"
}
EOF
    exit 2
  }

  read -r config_file image_name <<< "$args"

  echo "INFO: Version detection orchestrator starting for image: $image_name" >&2
  echo "INFO: Config file: $config_file" >&2

  # Run detection with fallback logic
  local result
  local exit_code

  result=$(run_detection_with_fallback "$config_file" "$image_name") || {
    exit_code=$?
    echo "$result"
    exit $exit_code
  }

  echo "$result"
  exit 0
}

# Run main function
main "$@"
