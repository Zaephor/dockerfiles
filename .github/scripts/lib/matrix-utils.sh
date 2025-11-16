#!/usr/bin/env bash
# Matrix utility functions for GitHub Actions dynamic matrix generation
# Provides JSON output and logging helpers for matrix generation decisions
#
# Usage: source .github/scripts/lib/matrix-utils.sh
# Required: bash 4.0+, jq

set -o pipefail

# ============================================================================
# JSON Output Helper: Create matrix entry
# ============================================================================

# Creates a single matrix entry (image object)
#
# Parameters:
#   IMAGE_NAME: Name of the image (e.g., "hello-world")
#   VERSION: Version detected for the image
#   REASON: Why this image is being built
#     - "files_changed": Dockerfile or data files modified
#     - "version_changed": New upstream version detected
#     - "no_history": No history file (first build)
#     - "force_rebuild": Manual force rebuild requested
#     - "version_detection_failed": Version detector failed
#   ARCHITECTURES: (optional) Space-separated list of architectures (e.g., "amd64 arm64")
#
# Returns:
#   JSON object to stdout: {"name":"...","version":"...","reason":"...","architectures":[...]}
#   Exit 0: Success
#   Exit 1: Invalid parameters
matrix_create_entry() {
    local image_name="$1"
    local version="$2"
    local reason="$3"
    local architectures="${4:-}"  # Optional architecture list

    # Validate inputs
    if [[ -z "$image_name" ]]; then
        echo "ERROR: image_name is required" >&2
        return 1
    fi

    if [[ -z "$reason" ]]; then
        echo "ERROR: reason is required" >&2
        return 1
    fi

    # Version can be empty (for failures)
    # Create JSON object with proper escaping
    if [[ -n "$architectures" ]]; then
        # Convert space-separated architectures to JSON array
        # Parse manually to handle whitespace correctly
        local arch_array='['
        local first=true

        for arch in ${architectures}; do
            if [[ "$first" == true ]]; then
                arch_array="${arch_array}\"${arch}\""
                first=false
            else
                arch_array="${arch_array},\"${arch}\""
            fi
        done
        arch_array="${arch_array}]"

        jq -n \
            --arg name "$image_name" \
            --arg version "${version:-}" \
            --arg reason "$reason" \
            --argjson architectures "$arch_array" \
            '{name: $name, version: $version, reason: $reason, architectures: $architectures}' || return 1
    else
        # No architectures specified (fallback for compatibility)
        jq -n \
            --arg name "$image_name" \
            --arg version "${version:-}" \
            --arg reason "$reason" \
            '{name: $name, version: $version, reason: $reason}' || return 1
    fi

    return 0
}

# ============================================================================
# JSON Output Helper: Build complete matrix
# ============================================================================

# Builds the complete GitHub Actions matrix JSON from an array of entries
#
# Expects stdin to contain JSON objects (one per line, as produced by matrix_create_entry)
# Outputs: {"image":[...]} format compatible with GitHub Actions fromJson()
#
# Parameters: None (reads from stdin)
#
# Returns:
#   Complete matrix JSON to stdout
#   Exit 0: Success
#   Exit 1: jq error
matrix_build_json() {
    # Read array of matrix entries and build the final matrix structure
    # Use -c for compact output (no newlines) required by GitHub Actions
    jq -sc '{"image": .}' 2>/dev/null
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        echo "ERROR: Failed to build matrix JSON" >&2
        return 1
    fi

    return 0
}

# ============================================================================
# JSON Output Helper: Create empty matrix
# ============================================================================

# Creates an empty matrix (no images to build)
#
# Parameters: None
#
# Returns:
#   Empty matrix JSON: {"image":[]}
matrix_create_empty() {
    echo '{"image":[]}'
    return 0
}

# ============================================================================
# Logging Helper: Log matrix decision
# ============================================================================

# Logs a matrix generation decision for an image
#
# Parameters:
#   IMAGE_NAME: Name of the image
#   VERSION: Detected version
#   REASON: Reason for build/skip decision
#   INCLUDED: "true" if included in matrix, "false" if skipped
#
# Returns:
#   Exit 0: Always (logging never fails)
matrix_log_decision() {
    local image_name="$1"
    local version="$2"
    local reason="$3"
    local included="$4"
    local variant="${5:-}"  # Optional variant parameter

    local decision
    if [[ "$included" == "true" ]]; then
        decision="INCLUDE"
    else
        decision="SKIP"
    fi

    # Include variant in output if provided
    # Output to stderr to avoid mixing with JSON on stdout
    if [[ -n "$variant" && "$variant" != "default" ]]; then
        echo "Matrix Decision: [$decision] Image: $image_name, Variant: $variant, Version: ${version:-unknown}, Reason: $reason" >&2
    else
        echo "Matrix Decision: [$decision] Image: $image_name, Version: ${version:-unknown}, Reason: $reason" >&2
    fi
    return 0
}

# ============================================================================
# Logging Helper: Log matrix generation start
# ============================================================================

# Logs the start of matrix generation
#
# Parameters:
#   IMAGE_COUNT: Number of images to process
#
# Returns:
#   Exit 0: Always
matrix_log_start() {
    local image_count="$1"
    echo "Matrix Generation: Starting - Processing $image_count images" >&2
    return 0
}

# ============================================================================
# Logging Helper: Log matrix generation complete
# ============================================================================

# Logs the completion of matrix generation
#
# Parameters:
#   INCLUDED_COUNT: Number of images included in matrix
#   TOTAL_COUNT: Total number of images processed
#
# Returns:
#   Exit 0: Always
matrix_log_complete() {
    local included_count="$1"
    local total_count="$2"

    echo "Matrix Generation: Complete - $included_count/$total_count images included for building" >&2
    return 0
}

# ============================================================================
# Logging Helper: Log error during matrix generation
# ============================================================================

# Logs an error during matrix generation
#
# Parameters:
#   ERROR_MESSAGE: Description of the error
#   FALLBACK_ACTION: What action will be taken (e.g., "Building all images")
#
# Returns:
#   Exit 0: Always
matrix_log_error() {
    local error_message="$1"
    local fallback_action="$2"

    echo "ERROR: Matrix Generation Failed: $error_message" >&2
    echo "Fallback Action: $fallback_action" >&2
    return 0
}

# ============================================================================
# Output Helper: Set GitHub Actions output
# ============================================================================

# Sets a GitHub Actions output variable
#
# Parameters:
#   OUTPUT_NAME: Name of the output (e.g., "matrix")
#   OUTPUT_VALUE: Value to set (e.g., JSON string)
#
# Returns:
#   Exit 0: Success
#   Exit 1: Missing GITHUB_OUTPUT environment variable
matrix_set_output() {
    local output_name="$1"
    local output_value="$2"

    if [[ -z "$GITHUB_OUTPUT" ]]; then
        echo "ERROR: GITHUB_OUTPUT not set (not running in GitHub Actions)" >&2
        return 1
    fi

    echo "${output_name}=${output_value}" >> "$GITHUB_OUTPUT"
    return 0
}

# ============================================================================
# Validation: Check required tools
# ============================================================================

# Validates that required tools are available
#
# Parameters: None
#
# Returns:
#   Exit 0: All required tools available
#   Exit 1: One or more required tools missing
matrix_validate_tools() {
    local missing_tools=()

    # Check for jq
    if ! command -v jq &>/dev/null; then
        missing_tools+=("jq")
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo "ERROR: Required tools missing: ${missing_tools[*]}" >&2
        return 1
    fi

    return 0
}

# ============================================================================
# Matrix Expansion: Expand image entries to image+architecture combinations
# ============================================================================

# Expands matrix JSON to create separate entries for each architecture
#
# Takes a matrix in {"image":[...]} format where each image has an architectures array,
# and expands it to create one entry per (image, architecture) combination.
#
# Parameters:
#   $1 - Matrix JSON string in {"image":[...]} format
#
# Outputs:
#   Expanded matrix in {"config":[...]} format for GitHub Actions
#
# Returns:
#   Exit 0: Success
#   Exit 1: jq error or invalid input
matrix_expand_for_architectures() {
    local matrix_json="$1"

    if [[ -z "$matrix_json" ]]; then
        echo "ERROR: matrix_json is required" >&2
        return 1
    fi

    # Expand each image entry to create separate entries for each architecture
    # Each entry gets: image (original), arch, platform (linux/arch), runs-on (runner type)
    local expanded
    expanded=$(echo "$matrix_json" | jq -c '
        .image | map(
            . as $img |
            (.architectures // ["amd64", "arm64"]) | map({
                image: $img,
                arch: .,
                platform: (if . == "amd64" then "linux/amd64" elif . == "arm64" then "linux/arm64" else "linux/\(.)" end),
                "runs-on": (if . == "amd64" then "ubuntu-latest" elif . == "arm64" then "ubuntu-24.04-arm" else "ubuntu-latest" end)
            })
        ) | flatten | {config: .}
    ' 2>/dev/null)

    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo "ERROR: Failed to expand matrix for architectures" >&2
        return 1
    fi

    echo "$expanded"
    return 0
}
