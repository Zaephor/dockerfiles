#!/usr/bin/env bash
# validate-workflow-inputs.sh - Validate GitHub Actions workflow_dispatch inputs
#
# Usage:
#   validate-workflow-inputs.sh \
#     [--image-filter IMAGES] \
#     [--skip-images IMAGES] \
#     [--version-override OVERRIDES] \
#     [--repo-root PATH]
#
# Description:
#   Validates workflow_dispatch manual trigger inputs against available images.
#   Ensures image names exist and version override format is correct.
#
# Exit Codes:
#   0 - All inputs valid
#   1 - Invalid input detected
#
# Dependencies:
#   - logging.sh (structured logging)

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source logging library
source "${SCRIPT_DIR}/lib/logging.sh"

# Global variables
IMAGE_FILTER=""
SKIP_IMAGES=""
VERSION_OVERRIDE=""
REPO_ROOT="."

#######################################
# Parse command-line arguments
#######################################
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --image-filter)
        IMAGE_FILTER="$2"
        shift 2
        ;;
      --skip-images)
        SKIP_IMAGES="$2"
        shift 2
        ;;
      --version-override)
        VERSION_OVERRIDE="$2"
        shift 2
        ;;
      --repo-root)
        REPO_ROOT="$2"
        shift 2
        ;;
      *)
        log_error "SYSTEM" "-" "VALIDATION" "Unknown option: $1"
        exit 1
        ;;
    esac
  done

  return 0
}

#######################################
# Get list of available image directories
#######################################
get_image_dirs() {
  find "$REPO_ROOT" -maxdepth 1 -type d -name '[^.].*' \
    ! -name '.github' \
    ! -name 'docs' \
    ! -name 'research' \
    ! -name 'specs' \
    ! -name 'tests' \
    | sed 's|^\./||' \
    | sed "s|^${REPO_ROOT}/||" \
    | sort
}

#######################################
# Validate image_filter input
#######################################
validate_image_filter() {
  [[ -z "$IMAGE_FILTER" ]] && return 0

  log_structured "SYSTEM" "-" "VALIDATION" "Validating image_filter: $IMAGE_FILTER"

  local image_dirs
  image_dirs=$(get_image_dirs)

  while IFS=',' read -r filter_image; do
    filter_image=$(echo "$filter_image" | xargs)

    if ! echo "$image_dirs" | grep -q "^${filter_image}$"; then
      log_error "SYSTEM" "-" "VALIDATION" "Invalid image in image_filter: $filter_image"
      echo "Available images: $image_dirs" >&2
      return 1
    fi
  done <<< "$IMAGE_FILTER"

  return 0
}

#######################################
# Validate skip_images input
#######################################
validate_skip_images() {
  [[ -z "$SKIP_IMAGES" ]] && return 0

  log_structured "SYSTEM" "-" "VALIDATION" "Validating skip_images: $SKIP_IMAGES"

  local image_dirs
  image_dirs=$(get_image_dirs)

  while IFS=',' read -r skip_image; do
    skip_image=$(echo "$skip_image" | xargs)

    if ! echo "$image_dirs" | grep -q "^${skip_image}$"; then
      log_error "SYSTEM" "-" "VALIDATION" "Invalid image in skip_images: $skip_image"
      echo "Available images: $image_dirs" >&2
      return 1
    fi
  done <<< "$SKIP_IMAGES"

  return 0
}

#######################################
# Validate version_override input
#######################################
validate_version_override() {
  [[ -z "$VERSION_OVERRIDE" ]] && return 0

  log_structured "SYSTEM" "-" "VALIDATION" "Validating version_override format"

  local image_dirs
  image_dirs=$(get_image_dirs)

  # Split by comma, then parse each image=version pair
  while IFS='=' read -r override_image override_version; do
    override_image=$(echo "$override_image" | xargs)

    if ! echo "$image_dirs" | grep -q "^${override_image}$"; then
      log_error "SYSTEM" "-" "VALIDATION" "Invalid image in version_override: $override_image"
      echo "Available images: $image_dirs" >&2
      return 1
    fi

    if [[ -z "$override_version" ]]; then
      log_error "SYSTEM" "-" "VALIDATION" "Empty version in version_override for image: $override_image"
      return 1
    fi
  done <<< "$(echo "$VERSION_OVERRIDE" | sed 's/,/\n/g')"

  return 0
}

#######################################
# Main validation
#######################################
main() {
  parse_args "$@"

  # Run all validations
  validate_image_filter || exit 1
  validate_skip_images || exit 1
  validate_version_override || exit 1

  log_structured "SYSTEM" "-" "VALIDATION" "All workflow_dispatch inputs validated successfully"
  exit 0
}

# Run main function
main "$@"
