#!/usr/bin/env bash
# Shared utility functions for local testing scripts
# Source this file: source "$(dirname "$0")/lib/local-common.sh"

set -euo pipefail

# Find image directory (handles running from repo root or image dir)
# Returns the absolute path to the image directory
find_image_dir() {
    local image_name="$1"
    local current_dir
    current_dir=$(pwd)

    if [ -f "metadata.yaml" ] && [ -f "Dockerfile" ]; then
        # Already in image directory
        echo "$current_dir"
        return 0
    elif [ -d "$image_name" ] && [ -f "$image_name/metadata.yaml" ] && [ -f "$image_name/Dockerfile" ]; then
        # In repo root, image dir specified
        echo "$current_dir/$image_name"
        return 0
    else
        echo "ERROR: Image directory not found: $image_name" >&2
        echo "Make sure you're in the repository root or an image directory" >&2
        return 4
    fi
}

# Read YAML field from metadata.yaml using yq
# Returns the field value or "null" if not found
get_metadata_field() {
    local file="$1"
    local field="$2"

    if [ ! -f "$file" ]; then
        echo "ERROR: File not found: $file" >&2
        return 4
    fi

    yq eval ".$field" "$file" 2>/dev/null || echo "null"
}

# Validate required YAML fields exist and are non-empty
# Returns 0 if all fields present, 1 if any missing
validate_required_fields() {
    local file="$1"
    shift
    local fields=("$@")
    local missing=()

    for field in "${fields[@]}"; do
        local value
        value=$(get_metadata_field "$file" "$field")
        if [ "$value" == "null" ] || [ -z "$value" ]; then
            missing+=("$field")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo "ERROR: Required fields missing from metadata.yaml: ${missing[*]}" >&2
        return 1
    fi

    return 0
}

# Check if a command exists
# Returns 0 if command found, 1 if not found
command_exists() {
    command -v "$1" &>/dev/null
}

# Get all available detector scripts
# Returns array of detector script names (without path or .sh extension)
get_available_detectors() {
    local detector_dir=".github/scripts/detectors"
    if [ ! -d "$detector_dir" ]; then
        return 1
    fi

    for detector in "$detector_dir"/*.sh; do
        if [ -f "$detector" ]; then
            basename "$detector" .sh
        fi
    done
}

# Convert version_source from metadata.yaml to detector script name
# Maps: github_releases → github-releases, github_tags → github-tags, etc.
normalize_detector_name() {
    local source="$1"
    echo "$source" | sed 's/_/-/g'
}

# Check if image has history.jsonl file
# Returns 0 if exists, 1 if not
has_history() {
    local image_dir="$1"
    [ -f "$image_dir/history.jsonl" ]
}

# Get latest version from history.jsonl
# Returns version string or empty if no history
get_latest_version_from_history() {
    local history_file="$1"

    if [ ! -f "$history_file" ]; then
        echo ""
        return 0
    fi

    # Get last line (latest build), extract version field
    tail -1 "$history_file" | jq -r '.version' 2>/dev/null || echo ""
}

# Check if git diff contains changes to specific image
# Returns 0 if changes found, 1 if no changes
check_git_changes() {
    local image_name="$1"

    # Check if image directory or Dockerfile changed
    git diff --name-only HEAD~1 2>/dev/null | grep -E "^${image_name}/" >/dev/null 2>&1
}

# Format output message with checkmark
success_message() {
    echo "✓ $*"
}

# Format output message with error indicator
error_message() {
    echo "✗ $*" >&2
}

# Format output message with info indicator
info_message() {
    echo "ℹ $*"
}

# Print a section header
print_header() {
    echo ""
    echo "=== $* ==="
    echo ""
}

# Print verbose output if VERBOSE mode is enabled
debug() {
    if [ "${VERBOSE:-false}" = "true" ]; then
        echo "[DEBUG] $*" >&2
    fi
}

export -f find_image_dir
export -f get_metadata_field
export -f validate_required_fields
export -f command_exists
export -f get_available_detectors
export -f normalize_detector_name
export -f has_history
export -f get_latest_version_from_history
export -f check_git_changes
export -f success_message
export -f error_message
export -f info_message
export -f print_header
export -f debug
