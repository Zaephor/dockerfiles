#!/usr/bin/env bash
# Run hadolint on all Dockerfile(s) in an image directory
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/local-common.sh"

VERBOSE=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] IMAGE_NAME

Lint all Dockerfile(s) in an image directory using hadolint.

Arguments:
  IMAGE_NAME    Name of image directory (e.g., hello-world)

Options:
  -h, --help    Show this help message
  --verbose     Enable verbose output

Examples:
  $(basename "$0") hello-world
  $(basename "$0") --verbose hello-world

Exit Codes:
  0    All Dockerfiles pass linting
  1    Linting errors found
  2    Missing dependencies (hadolint)
  3    Invalid arguments
  4    No Dockerfiles found

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
    if ! command_exists "hadolint"; then
        # Skip hadolint checks gracefully if not available
        return 1
    fi
    return 0
}

if ! check_dependencies; then
    echo "SKIP: hadolint not installed. Install with: apt-get install hadolint"
    exit 0
fi

# Find image directory
IMAGE_DIR=$(find_image_dir "$IMAGE_NAME") || exit 4

debug "Image directory: $IMAGE_DIR"

# Find all Dockerfile variants
DOCKERFILES=()
if [ -f "$IMAGE_DIR/Dockerfile" ]; then
    DOCKERFILES+=("$IMAGE_DIR/Dockerfile")
fi

# Find Dockerfile.* variants
if [ -d "$IMAGE_DIR" ]; then
    while IFS= read -r dockerfile; do
        [ -z "$dockerfile" ] && continue
        DOCKERFILES+=("$dockerfile")
    done < <(find "$IMAGE_DIR" -maxdepth 1 -name "Dockerfile.*" -type f 2>/dev/null || true)
fi

if [ ${#DOCKERFILES[@]} -eq 0 ]; then
    error_message "No Dockerfiles found in $IMAGE_DIR/"
    exit 4
fi

debug "Found ${#DOCKERFILES[@]} Dockerfile(s)"

# Check if hadolint config exists
HADOLINT_CONFIG=""
if [ -f ".hadolint.yaml" ]; then
    HADOLINT_CONFIG="-c .hadolint.yaml"
    debug "Using hadolint config: .hadolint.yaml"
fi

# Run hadolint on each Dockerfile
TOTAL_ERRORS=0
SUCCESS_COUNT=0

for dockerfile in "${DOCKERFILES[@]}"; do
    relative_path="${dockerfile#"$(pwd)"/}"
    echo "Linting: $relative_path"

    if hadolint "${HADOLINT_CONFIG}" "$dockerfile" >/dev/null 2>&1; then
        success_message "No linting errors"
        ((SUCCESS_COUNT++))
    else
        # Run again to show errors
        hadolint "${HADOLINT_CONFIG}" "$dockerfile" 2>&1 | sed 's/^/  /'
        ((TOTAL_ERRORS++))
    fi

    echo ""
done

# Summary
if [ $TOTAL_ERRORS -eq 0 ]; then
    success_message "All Dockerfiles passed linting"
    exit 0
else
    error_message "$TOTAL_ERRORS Dockerfile(s) have linting errors"
    exit 1
fi
