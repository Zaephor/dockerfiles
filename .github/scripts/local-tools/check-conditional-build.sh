#!/usr/bin/env bash
# Check if an image would be built based on change detection logic
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/local-common.sh"

VERBOSE=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] IMAGE_NAME

Check if an image would be built based on conditional build logic.
Evaluates git changes, version changes, and history.

Arguments:
  IMAGE_NAME    Name of image directory (e.g., hello-world)

Options:
  -h, --help    Show this help message
  --verbose     Enable verbose output

Examples:
  $(basename "$0") hello-world
  $(basename "$0") --verbose hello-world

Exit Codes:
  0    Image would be built
  1    Image would be skipped
  2    Missing dependencies
  3    Invalid arguments
  4    Image directory not found

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
    local deps=("git" "jq" "yq")

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

print_header "Checking: $IMAGE_NAME"

# Check for git changes in image directory
HAS_GIT_CHANGES=false
GIT_CHANGES=()

if git diff --name-only HEAD~1 2>/dev/null | grep -E "^${IMAGE_NAME}/" >/dev/null 2>&1; then
    HAS_GIT_CHANGES=true
    while IFS= read -r file; do
        GIT_CHANGES+=("  - $file (modified)")
    done < <(git diff --name-only HEAD~1 | grep -E "^${IMAGE_NAME}/")
fi

if [ "$HAS_GIT_CHANGES" = true ]; then
    echo "Git changes detected:"
    printf '%s\n' "${GIT_CHANGES[@]}"
    echo ""
    echo "Conclusion: Image WOULD BE BUILT"
    echo "Reason: Files changed (Dockerfile, metadata.yaml, or data directory)"
    exit 0
fi

debug "No git changes detected"

# Check version history
HISTORY_FILE="$IMAGE_DIR/history.jsonl"

if [ ! -f "$HISTORY_FILE" ]; then
    debug "No history file found"
    echo "No build history found"
    echo ""
    echo "Conclusion: Image WOULD BE BUILT"
    echo "Reason: First time building (no history.jsonl)"
    exit 0
fi

# Get latest version from history
LATEST_VERSION=$(get_latest_version_from_history "$HISTORY_FILE")
debug "Latest version in history: $LATEST_VERSION"

if [ -z "$LATEST_VERSION" ]; then
    echo "Could not read version from history"
    echo ""
    echo "Conclusion: Image WOULD BE BUILT"
    echo "Reason: History file exists but empty or corrupted"
    exit 0
fi

echo "Latest version in history: $LATEST_VERSION"

# Try to detect current version via the orchestrator (handles detector
# dispatch, fallback chains, and per-detector argument handling).
CURRENT_VERSION=""
if [ -f "$IMAGE_DIR/metadata.yaml" ]; then
    VERSION_SOURCE_TYPE=$(yq eval '.version_source.type // .version_source[0].type // ""' \
        "$IMAGE_DIR/metadata.yaml" 2>/dev/null || echo "")
    ORCHESTRATOR=".github/scripts/version-detection.sh"
    if [ -n "$VERSION_SOURCE_TYPE" ] && [ "$VERSION_SOURCE_TYPE" != "null" ] && [ -f "$ORCHESTRATOR" ]; then
        debug "Calling orchestrator to get current version..."
        if RESULT=$("$ORCHESTRATOR" --config "$IMAGE_DIR/metadata.yaml" --image-name "$IMAGE_NAME" --variant default 2>/dev/null); then
            CURRENT_VERSION=$(echo "$RESULT" | jq -r '.version // empty' 2>/dev/null || echo "")
            [ -n "$CURRENT_VERSION" ] && debug "Current version: $CURRENT_VERSION"
        fi
    fi
fi

if [ -z "$CURRENT_VERSION" ]; then
    echo "Detected version: (could not detect - detector not available or failed)"
    echo ""
    echo "Conclusion: Image WOULD BE BUILT"
    echo "Reason: Could not detect current version for comparison"
    exit 0
fi

echo "Detected version: $CURRENT_VERSION"

# Compare versions
if [ "$LATEST_VERSION" = "$CURRENT_VERSION" ]; then
    echo ""
    echo "Conclusion: Image WOULD BE SKIPPED"
    echo "Reason: No changes, version unchanged"
    exit 1
else
    echo ""
    echo "Conclusion: Image WOULD BE BUILT"
    echo "Reason: New version detected ($LATEST_VERSION → $CURRENT_VERSION)"
    exit 0
fi
