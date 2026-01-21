#!/bin/bash
# verify-image.sh - Verify a built container image works correctly
#
# Reads verification configuration from metadata.yaml and runs appropriate
# checks to validate the container image before publishing.
#
# Usage:
#   ./verify-image.sh --image-name hello-world --image-tag 1.0.0 --config ./hello-world/metadata.yaml
#   ./verify-image.sh -n hello-world -t 1.0.0 -c ./hello-world/metadata.yaml
#
# Exit Codes:
#   0: Verification passed
#   1: Verification failed
#   2: Configuration error
#   3: Timeout
#   4: Invalid arguments

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
source "${SCRIPT_DIR}/lib/verification.sh"

# Default values
IMAGE_NAME=""
IMAGE_TAG="latest"  # Default to "latest" if not provided (optional for digest refs)
CONFIG_FILE=""
PLATFORM=""
OUTPUT_JSON=false
QUIET=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Verify a built container image works correctly.

Options:
  -n, --image-name NAME    Name of the image (required)
  -t, --image-tag TAG      Tag of the image (default: latest)
  -c, --config FILE        Path to metadata.yaml (required)
  -p, --platform PLATFORM  Platform to verify (e.g., linux/amd64)
  --json                   Output result as JSON
  -q, --quiet              Suppress non-error output
  -h, --help               Show this help message

Examples:
  $(basename "$0") -n wyoming-satellite -t 1.0.0 -c ./rhasspy/wyoming-satellite/metadata.yaml
  $(basename "$0") --image-name hello-world --image-tag latest --config ./hello-world/metadata.yaml --json

Exit Codes:
  0    Verification passed
  1    Verification failed
  2    Configuration error
  3    Timeout
  4    Invalid arguments

EOF
}

# Parse command line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--image-name)
        IMAGE_NAME="$2"
        shift 2
        ;;
      -t|--image-tag)
        IMAGE_TAG="$2"
        shift 2
        ;;
      -c|--config)
        CONFIG_FILE="$2"
        shift 2
        ;;
      -p|--platform)
        PLATFORM="$2"
        shift 2
        ;;
      --json)
        OUTPUT_JSON=true
        shift
        ;;
      -q|--quiet)
        QUIET=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "ERROR: Unknown option: $1" >&2
        usage >&2
        exit 4
        ;;
    esac
  done
}

# Validate required arguments
validate_args() {
  local errors=()

  if [[ -z "$IMAGE_NAME" ]]; then
    errors+=("--image-name is required")
  fi

  # IMAGE_TAG is optional - defaults to "latest" for digest references

  if [[ -z "$CONFIG_FILE" ]]; then
    errors+=("--config is required")
  elif [[ ! -f "$CONFIG_FILE" ]]; then
    errors+=("Config file not found: $CONFIG_FILE")
  fi

  if [[ ${#errors[@]} -gt 0 ]]; then
    for error in "${errors[@]}"; do
      echo "ERROR: $error" >&2
    done
    echo "" >&2
    usage >&2
    exit 4
  fi
}

# Check required dependencies
check_dependencies() {
  local missing=()
  local deps=("docker" "yq" "jq")

  for cmd in "${deps[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required dependencies: ${missing[*]}" >&2
    exit 2
  fi
}

main() {
  parse_args "$@"
  validate_args
  check_dependencies

  # Suppress output if quiet mode
  if [[ "$QUIET" == "true" ]] && [[ "$OUTPUT_JSON" != "true" ]]; then
    exec 1>/dev/null
  fi

  # Parse verification config to get mode for JSON output
  local config
  local mode
  config=$(parse_verification_config "$CONFIG_FILE") || {
    if [[ "$OUTPUT_JSON" == "true" ]]; then
      output_json_result "$IMAGE_NAME" "$IMAGE_TAG" "unknown" "error" "Failed to parse config" 2
    fi
    exit 2
  }
  mode=$(get_verification_mode "$config")
  mode="${mode:-none}"

  # Run verification
  local exit_code=0
  local message=""

  run_verification "$IMAGE_NAME" "$IMAGE_TAG" "$CONFIG_FILE" "$PLATFORM" || exit_code=$?

  # Determine status and message based on exit code
  local status
  case $exit_code in
    0)
      status="passed"
      message="Verification completed successfully"
      ;;
    1)
      status="failed"
      message="Verification failed"
      ;;
    2)
      status="error"
      message="Configuration error"
      ;;
    3)
      status="failed"
      message="Verification timed out"
      ;;
    *)
      status="error"
      message="Unknown error"
      ;;
  esac

  # Output JSON result if requested
  if [[ "$OUTPUT_JSON" == "true" ]]; then
    output_json_result "$IMAGE_NAME" "$IMAGE_TAG" "$mode" "$status" "$message" "$exit_code"
  fi

  exit $exit_code
}

main "$@"
