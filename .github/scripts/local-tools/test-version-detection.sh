#!/usr/bin/env bash
# Test version detection locally by calling the appropriate detector
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/local-common.sh"

VERBOSE=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] IMAGE_NAME

Test version detection for a Docker image by running its configured detector locally.

Arguments:
  IMAGE_NAME    Name of image directory (e.g., hello-world)

Options:
  -h, --help    Show this help message
  --verbose     Enable verbose output

Examples:
  $(basename "$0") hello-world
  $(basename "$0") --verbose hello-world

Exit Codes:
  0    Version detected successfully
  1    Version detection failed
  2    Missing dependencies
  3    Invalid arguments
  4    metadata.yaml or detector script not found

EOF
}

# Parse arguments
if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
    usage
    exit 0
fi

if [[ "${1:-}" == "--verbose" ]]; then
    VERBOSE=true
    shift
fi

if [ $# -ne 1 ]; then
    usage
    exit 3
fi

IMAGE_NAME="$1"

# Check dependencies
check_dependencies() {
    local missing=()
    local deps=("yq" "jq")

    for cmd in "${deps[@]}"; do
        if ! command_exists "$cmd"; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        error_message "Missing required dependencies: ${missing[*]}"
        exit 2
    fi
}

check_dependencies

# Find image directory
IMAGE_DIR=$(find_image_dir "$IMAGE_NAME") || exit 4

debug "Image directory: $IMAGE_DIR"

METADATA_FILE="$IMAGE_DIR/metadata.yaml"

if [ ! -f "$METADATA_FILE" ]; then
    error_message "metadata.yaml not found in $IMAGE_DIR/"
    exit 4
fi

print_header "Detecting version for: $IMAGE_NAME"

# Get version source from metadata
VERSION_SOURCE=$(get_metadata_field "$METADATA_FILE" "version_source")
if [ "$VERSION_SOURCE" == "null" ] || [ -z "$VERSION_SOURCE" ]; then
    error_message "version_source not specified in metadata.yaml"
    exit 1
fi

echo "Version source: $VERSION_SOURCE"

# Find detector script
DETECTOR_NAME=$(normalize_detector_name "$VERSION_SOURCE")
DETECTOR_SCRIPT=".github/scripts/detectors/${DETECTOR_NAME}.sh"

if [ ! -f "$DETECTOR_SCRIPT" ]; then
    error_message "Detector script not found: $DETECTOR_SCRIPT"
    echo "Available detectors: $(get_available_detectors | tr '\n' ', ')" >&2
    exit 4
fi

debug "Detector script: $DETECTOR_SCRIPT"

# Get source configuration from metadata
SOURCE_CONFIG=$(yq eval '.source' "$METADATA_FILE" 2>/dev/null || echo "null")
if [ "$SOURCE_CONFIG" == "null" ]; then
    error_message "source configuration not found in metadata.yaml"
    exit 1
fi

echo "Calling detector: $DETECTOR_SCRIPT"
echo ""

# Call detector and capture output
if ! DETECTED_VERSION=$("$DETECTOR_SCRIPT" "$IMAGE_DIR" 2>&1); then
    echo ""
    error_message "Version detection failed"
    echo "Detector exit code: $?" >&2
    echo "Troubleshooting tips:" >&2
    echo "  - Check GitHub API rate limits: gh api rate_limit" >&2
    echo "  - Set GITHUB_TOKEN: export GITHUB_TOKEN=<token>" >&2
    echo "  - Verify source configuration in metadata.yaml matches detector expectations" >&2
    echo "  - Run detector with full output: $DETECTOR_SCRIPT $IMAGE_DIR" >&2
    exit 1
fi

echo ""
success_message "Version detection succeeded"
echo "Detected version: $DETECTED_VERSION"
exit 0
