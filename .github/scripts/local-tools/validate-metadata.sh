#!/usr/bin/env bash
# Validate metadata.yaml syntax and schema for a Docker image
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/local-common.sh"

VERBOSE=false

# Valid values for enum fields
VALID_VERSION_SOURCES=("github_releases" "binary_version" "docker_tag" "http_json")
VALID_ARCHITECTURES=("amd64" "arm64" "386" "ppc64le" "s390x")

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] IMAGE_NAME

Validate metadata.yaml syntax and schema for a Docker image.

Arguments:
  IMAGE_NAME    Name of image directory (e.g., hello-world)

Options:
  -h, --help    Show this help message
  --verbose     Enable verbose output

Examples:
  $(basename "$0") hello-world
  $(basename "$0") --verbose hello-world

Exit Codes:
  0    Validation passed
  1    Validation failed (YAML syntax or schema error)
  2    Missing dependencies (yq, jq)
  3    Invalid arguments
  4    metadata.yaml not found

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
        echo "Install with: apt-get install ${missing[*]}" >&2
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
    echo "Create metadata.yaml with required fields: name, version_source, source" >&2
    echo "See examples/ directory for templates" >&2
    exit 4
fi

# Validate YAML syntax
debug "Validating YAML syntax..."
if ! yq eval '.' "$METADATA_FILE" >/dev/null 2>&1; then
    error_message "YAML syntax error in $METADATA_FILE"
    yq eval '.' "$METADATA_FILE" 2>&1 | head -5 | sed 's/^/  /' >&2
    exit 1
fi
success_message "YAML syntax valid"

# Validate required fields
debug "Validating required fields..."
if ! validate_required_fields "$METADATA_FILE" "name" "version_source" "source"; then
    exit 1
fi
success_message "Required fields present: name, version_source, source"

# Validate version_source enum
debug "Validating version_source value..."
VERSION_SOURCE=$(get_metadata_field "$METADATA_FILE" "version_source")
if [ "$VERSION_SOURCE" == "null" ] || [ -z "$VERSION_SOURCE" ]; then
    error_message "version_source is required"
    exit 1
fi

valid=false
for valid_source in "${VALID_VERSION_SOURCES[@]}"; do
    if [ "$VERSION_SOURCE" == "$valid_source" ]; then
        valid=true
        break
    fi
done

if [ "$valid" = false ]; then
    error_message "version_source has invalid value: $VERSION_SOURCE"
    echo "Valid values: ${VALID_VERSION_SOURCES[*]}" >&2
    exit 1
fi
success_message "version_source value valid: $VERSION_SOURCE"

# Validate architectures if specified
debug "Validating architectures..."
ARCHITECTURES=$(yq eval '.architectures' "$METADATA_FILE" 2>/dev/null || echo "")
if [ -n "$ARCHITECTURES" ] && [ "$ARCHITECTURES" != "null" ]; then
    # Parse as array using jq
    if ! echo "$ARCHITECTURES" | yq eval -o=json '.' >/dev/null 2>&1; then
        error_message "architectures format invalid"
        exit 1
    fi

    # Check each architecture value
    while IFS= read -r arch; do
        arch="${arch//[[:space:]]/}"
        arch="${arch//\"/}"
        [ -z "$arch" ] && continue

        arch_valid=false
        for valid_arch in "${VALID_ARCHITECTURES[@]}"; do
            if [ "$arch" == "$valid_arch" ]; then
                arch_valid=true
                break
            fi
        done

        if [ "$arch_valid" = false ]; then
            error_message "Invalid architecture: $arch"
            echo "Valid values: ${VALID_ARCHITECTURES[*]}" >&2
            exit 1
        fi
    done < <(yq eval '.architectures[]' "$METADATA_FILE")

    success_message "Architectures valid: $(yq eval '.architectures | join(", ")' "$METADATA_FILE")"
else
    success_message "Architectures not specified (will auto-detect)"
fi

# Validate referenced Dockerfiles exist
debug "Checking Dockerfile references..."
VARIANTS=$(yq eval '.variants' "$METADATA_FILE" 2>/dev/null || echo "")
if [ -n "$VARIANTS" ] && [ "$VARIANTS" != "null" ]; then
    while IFS= read -r variant; do
        variant="${variant//[[:space:]]/}"
        variant="${variant//\"/}"
        [ -z "$variant" ] && continue

        DOCKERFILE="Dockerfile.$variant"
        if [ ! -f "$IMAGE_DIR/$DOCKERFILE" ]; then
            error_message "$DOCKERFILE referenced in variants but not found"
            exit 1
        fi
    done < <(yq eval '.variants[]' "$METADATA_FILE")
fi

if [ ! -f "$IMAGE_DIR/Dockerfile" ]; then
    error_message "Dockerfile not found in $IMAGE_DIR/"
    exit 1
fi

success_message "Metadata validation passed"
exit 0
