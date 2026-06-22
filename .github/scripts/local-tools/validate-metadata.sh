#!/usr/bin/env bash
# Validate metadata.yaml syntax and schema for a Docker image
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/local-common.sh"

VERBOSE=false

# Valid values for enum fields.
# version_source.type must match a detector script name (detectors/<type>.sh).
VALID_VERSION_SOURCES=("github_releases" "git_commit" "docker_tag" "docker_digest" "binary_version" "http_json")
VALID_ARCHITECTURES=("amd64" "arm64" "386" "ppc64le" "s390x")
VALID_VERIFICATION_MODES=("none" "python-cli" "binary" "command" "port")

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
    echo "Create metadata.yaml with required fields: name, version_source (a map with a 'type')" >&2
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
if ! validate_required_fields "$METADATA_FILE" "name" "version_source"; then
    exit 1
fi
success_message "Required fields present: name, version_source"

# Validate version_source is a map with a recognised type.
#
# Schema: version_source is a mapping carrying a 'type' plus detector-specific
# fields (the same object the detectors and orchestrator read). A fallback
# chain is expressed as a sequence of such mappings.
debug "Validating version_source..."
VERSION_SOURCE_KIND=$(yq eval '.version_source | type' "$METADATA_FILE" 2>/dev/null || echo "")

# Collect the type(s) declared. For a single map: .version_source.type.
# For a sequence (fallback chain): each element's .type.
declare -a DECLARED_TYPES=()
case "$VERSION_SOURCE_KIND" in
    "!!map")
        mapfile -t DECLARED_TYPES < <(yq eval '.version_source.type' "$METADATA_FILE" 2>/dev/null)
        ;;
    "!!seq")
        mapfile -t DECLARED_TYPES < <(yq eval '.version_source[].type' "$METADATA_FILE" 2>/dev/null)
        ;;
    *)
        error_message "version_source must be a map (a 'type' plus its fields), not a bare scalar"
        echo "Example:" >&2
        echo "  version_source:" >&2
        echo "    type: github_releases" >&2
        echo "    repo: owner/project" >&2
        exit 1
        ;;
esac

if [ ${#DECLARED_TYPES[@]} -eq 0 ]; then
    error_message "version_source is missing a 'type'"
    exit 1
fi

# Validate each declared type and its required fields.
for idx in "${!DECLARED_TYPES[@]}"; do
    vtype="${DECLARED_TYPES[$idx]}"

    if [ -z "$vtype" ] || [ "$vtype" == "null" ]; then
        error_message "version_source entry $((idx + 1)) is missing a 'type'"
        exit 1
    fi

    type_valid=false
    for valid_source in "${VALID_VERSION_SOURCES[@]}"; do
        if [ "$vtype" == "$valid_source" ]; then
            type_valid=true
            break
        fi
    done
    if [ "$type_valid" = false ]; then
        error_message "version_source type has invalid value: $vtype"
        echo "Valid values: ${VALID_VERSION_SOURCES[*]}" >&2
        exit 1
    fi

    # Base path to this entry's fields (single map vs. sequence element).
    if [ "$VERSION_SOURCE_KIND" == "!!seq" ]; then
        base=".version_source[$idx]"
    else
        base=".version_source"
    fi

    # Detector-specific required fields.
    required_fields=()
    case "$vtype" in
        github_releases) required_fields=("repo") ;;
        git_commit)      required_fields=("repo") ;;
        docker_tag)      required_fields=("registry" "image") ;;
        docker_digest)   required_fields=("registry" "image" "tag") ;;
        binary_version)  required_fields=("binary_path" "version_regex") ;;
        http_json)       required_fields=("url" "format" "path") ;;
    esac

    for field in "${required_fields[@]}"; do
        fval=$(yq eval "${base}.${field}" "$METADATA_FILE" 2>/dev/null || echo "null")
        if [ -z "$fval" ] || [ "$fval" == "null" ]; then
            error_message "version_source ($vtype) is missing required field: $field"
            exit 1
        fi
    done

    success_message "version_source type valid: $vtype"
done

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

# Validate verification config if present
debug "Validating verification config..."
VERIFICATION=$(yq eval '.verification' "$METADATA_FILE" 2>/dev/null || echo "")
if [ -n "$VERIFICATION" ] && [ "$VERIFICATION" != "null" ]; then
    # Get verification mode
    VERIFY_MODE=$(yq eval '.verification.mode' "$METADATA_FILE" 2>/dev/null || echo "")

    if [ -z "$VERIFY_MODE" ] || [ "$VERIFY_MODE" == "null" ]; then
        error_message "verification.mode is required when verification section is present"
        exit 1
    fi

    # Validate mode is valid
    mode_valid=false
    for valid_mode in "${VALID_VERIFICATION_MODES[@]}"; do
        if [ "$VERIFY_MODE" == "$valid_mode" ]; then
            mode_valid=true
            break
        fi
    done

    if [ "$mode_valid" = false ]; then
        error_message "verification.mode has invalid value: $VERIFY_MODE"
        echo "Valid values: ${VALID_VERIFICATION_MODES[*]}" >&2
        exit 1
    fi

    # Mode-specific validation
    case "$VERIFY_MODE" in
        python-cli)
            MODULE=$(yq eval '.verification.module' "$METADATA_FILE" 2>/dev/null || echo "")
            if [ -z "$MODULE" ] || [ "$MODULE" == "null" ]; then
                error_message "verification.module is required for python-cli mode"
                exit 1
            fi
            ;;
        binary)
            BINARY=$(yq eval '.verification.binary' "$METADATA_FILE" 2>/dev/null || echo "")
            if [ -z "$BINARY" ] || [ "$BINARY" == "null" ]; then
                error_message "verification.binary is required for binary mode"
                exit 1
            fi
            ;;
        command)
            COMMANDS=$(yq eval '.verification.commands' "$METADATA_FILE" 2>/dev/null || echo "")
            if [ -z "$COMMANDS" ] || [ "$COMMANDS" == "null" ]; then
                error_message "verification.commands is required for command mode"
                exit 1
            fi
            # Validate commands is an array with at least one item
            CMD_COUNT=$(yq eval '.verification.commands | length' "$METADATA_FILE" 2>/dev/null || echo "0")
            if [ "$CMD_COUNT" -eq 0 ]; then
                error_message "verification.commands must have at least one command"
                exit 1
            fi
            ;;
        port)
            PORT=$(yq eval '.verification.port' "$METADATA_FILE" 2>/dev/null || echo "")
            if [ -z "$PORT" ] || [ "$PORT" == "null" ]; then
                error_message "verification.port is required for port mode"
                exit 1
            fi
            # Validate port is a number in valid range
            if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
                error_message "verification.port must be a valid port number (1-65535), got: $PORT"
                exit 1
            fi
            ;;
        none)
            # No additional validation needed for 'none' mode
            ;;
    esac

    success_message "Verification config valid: mode=$VERIFY_MODE"
else
    info_message "No verification config (consider adding verification section)"
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
