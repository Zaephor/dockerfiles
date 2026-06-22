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

# Determine the configured detector type from version_source.
# version_source is a map with a 'type' (or a sequence of such maps for a
# fallback chain); read the first declared type for reporting.
VERSION_SOURCE_KIND=$(yq eval '.version_source | type' "$METADATA_FILE" 2>/dev/null || echo "")
case "$VERSION_SOURCE_KIND" in
    "!!map") DETECTOR_TYPE=$(yq eval '.version_source.type' "$METADATA_FILE" 2>/dev/null) ;;
    "!!seq") DETECTOR_TYPE=$(yq eval '.version_source[0].type' "$METADATA_FILE" 2>/dev/null) ;;
    *)
        error_message "version_source must be a map with a 'type' (see examples/)"
        exit 1
        ;;
esac

if [ -z "$DETECTOR_TYPE" ] || [ "$DETECTOR_TYPE" == "null" ]; then
    error_message "version_source.type not specified in metadata.yaml"
    exit 1
fi

echo "Version source type: $DETECTOR_TYPE"

# Detection is run through the orchestrator so detector dispatch, fallback
# chains, and per-detector argument handling all match production behaviour.
ORCHESTRATOR=".github/scripts/version-detection.sh"
if [ ! -f "$ORCHESTRATOR" ]; then
    error_message "Orchestrator not found: $ORCHESTRATOR"
    exit 4
fi

echo "Running: $ORCHESTRATOR --config $METADATA_FILE --image-name $IMAGE_NAME --variant default"
echo ""

# Orchestrator emits a JSON result on stdout; logs go to stderr.
if ! RESULT=$("$ORCHESTRATOR" --config "$METADATA_FILE" --image-name "$IMAGE_NAME" --variant default 2>/dev/null); then
    echo ""
    error_message "Version detection failed"
    echo "Troubleshooting tips:" >&2
    echo "  - Check GitHub API rate limits: gh api rate_limit" >&2
    echo "  - Set GITHUB_TOKEN: export GITHUB_TOKEN=<token>" >&2
    echo "  - Verify version_source fields match the detector's expectations" >&2
    echo "  - Re-run with logs: DEBUG=true $ORCHESTRATOR --config $METADATA_FILE --image-name $IMAGE_NAME --variant default" >&2
    exit 1
fi

DETECTED_VERSION=$(echo "$RESULT" | jq -r '.version // empty' 2>/dev/null || echo "")
if [ -z "$DETECTED_VERSION" ]; then
    error_message "Version detection returned no version"
    echo "$RESULT" >&2
    exit 1
fi

echo ""
success_message "Version detection succeeded"
echo "Detected version: $DETECTED_VERSION"
exit 0
