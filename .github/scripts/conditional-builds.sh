#!/usr/bin/env bash
# Conditional build logic for Docker images
# Determines which images need building based on change detection and version history

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load required libraries
if [[ ! -f "$SCRIPT_DIR/lib/logging.sh" ]]; then
    echo "ERROR: logging.sh not found" >&2
    exit 1
fi
source "$SCRIPT_DIR/lib/logging.sh"

if [[ ! -f "$SCRIPT_DIR/lib/history.sh" ]]; then
    echo "ERROR: history.sh not found" >&2
    exit 1
fi
source "$SCRIPT_DIR/lib/history.sh"

# Determine if an image should be built
# Args:
#   $1: Image name
#   $2: Repository root
#   $3: Version detected
#   $4: Variant (optional) - determines which history file to read
# Returns:
#   0 on success (always), 1 on error
#   Outputs JSON to stdout with build decision
#   Format: {"image_name":"...","should_build":true/false,"reason":"...","version":"..."}
should_build_image() {
    local image_name="$1"
    local repo_root="${2:-.}"
    local version="$3"
    local variant="${4:-}"

    # Calculate history file path based on variant
    # - No variant or "default": history.jsonl
    # - With variant: history-${variant}.jsonl
    local history_file
    if [[ -z "$variant" ]] || [[ "$variant" == "default" ]]; then
        history_file="$repo_root/$image_name/history.jsonl"
    else
        history_file="$repo_root/$image_name/history-${variant}.jsonl"
    fi

    local should_build="false"
    local reason="unknown"

    # Check if history file exists
    if [[ ! -f "$history_file" ]]; then
        should_build="true"
        reason="no_history"
        log_decision "Image $image_name: Building (no history file exists)"
    else
        # Get last recorded version
        local last_version
        last_version=$(get_last_build_version "$history_file")

        # Check if version changed
        if [[ -n "$last_version" ]] && [[ "$version" != "$last_version" ]]; then
            should_build="true"
            reason="version_changed"
            log_decision "Image $image_name: Building (version changed: $last_version -> $version)"
        # Check if files changed (Dockerfile, metadata.yaml, or data/ directory)
        elif git_files_changed "$repo_root/$image_name" 2>/dev/null; then
            should_build="true"
            reason="files_changed"
            log_decision "Image $image_name: Building (files changed)"
        else
            # No changes detected
            should_build="false"
            reason="skip"
            log_decision "Image $image_name: Skipping (no changes detected)"
        fi
    fi

    # Output JSON to stdout
    echo "{\"image_name\":\"${image_name}\",\"should_build\":${should_build},\"reason\":\"${reason}\",\"version\":\"${version}\"}"

    return 0
}

# Check if files in image directory have changed
git_files_changed() {
    local image_dir="$1"

    # Get the relative path from repo root
    local image_name
    image_name=$(basename "$image_dir")

    # Check for changes in this image's directory
    # Compare against HEAD~1 (parent commit)
    if git diff --quiet HEAD~1 HEAD -- "$image_name/" 2>/dev/null; then
        # No changes
        return 1
    else
        # Files changed
        return 0
    fi
}

# Get last build version from history file
# Args:
#   $1: Path to history.jsonl
# Returns:
#   Last recorded version, or empty string if none
get_last_build_version() {
    local history_file="$1"

    if [[ ! -f "$history_file" ]]; then
        return 0
    fi

    # Get the last line and extract version field
    tail -1 "$history_file" 2>/dev/null | jq -r '.version // empty' 2>/dev/null || true
}

# Export functions
export -f should_build_image
export -f git_files_changed
export -f get_last_build_version
