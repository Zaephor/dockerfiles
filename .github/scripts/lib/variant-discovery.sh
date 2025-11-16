#!/usr/bin/env bash
# Variant Discovery Library
#
# Functions for discovering Dockerfile variants in image directories.
# Implements variant discovery following Constitution Principle 10:
# Scale Through Configuration, Not Code.
#
# Usage:
#   source .github/scripts/lib/variant-discovery.sh
#   discover_variants --image-dir /path/to/image
#   validate_variant_name "alpine"
#   get_dockerfile_path /path/to/image "alpine"

set -euo pipefail

# Source logging library for consistency
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

#######################################
# Discovers all Dockerfile variants in an image directory
#
# Scans for Dockerfile and Dockerfile.* files, extracts variant names,
# and returns JSON output with sorted variant list. Default variant
# (Dockerfile) appears first if it exists, otherwise only named variants
# are returned.
#
# Arguments:
#   --image-dir <path>: Absolute path to image directory (required)
#
# Output (stdout):
#   JSON object with variants array:
#   {
#     "variants": [
#       { "name": "default", "dockerfile": "/path/to/Dockerfile" },
#       { "name": "alpine", "dockerfile": "/path/to/Dockerfile.alpine" }
#     ]
#   }
#
#   Or if no default Dockerfile exists:
#   {
#     "variants": [
#       { "name": "act-22.04", "dockerfile": "/path/to/Dockerfile.act-22.04" },
#       { "name": "act-24.04", "dockerfile": "/path/to/Dockerfile.act-24.04" }
#     ]
#   }
#
# Exit codes:
#   0: Success
#   1: Image directory not found
#   2: No Dockerfile or Dockerfile.* variants found in directory
#
#######################################
discover_variants() {
    local image_dir=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --image-dir)
                image_dir="$2"
                shift 2
                ;;
            *)
                error "Unknown argument: $1"
                return 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$image_dir" ]]; then
        error "Missing required argument: --image-dir"
        return 1
    fi

    # Check directory exists
    if [[ ! -d "$image_dir" ]]; then
        error "Image directory not found: $image_dir"
        return 1
    fi

    # Find all Dockerfile variants (Dockerfile and Dockerfile.*)
    local default_dockerfile="${image_dir}/Dockerfile"
    local variants=()
    local has_default=false

    # Add default variant if it exists (optional)
    if [[ -f "$default_dockerfile" ]]; then
        variants+=("default:${default_dockerfile}")
        has_default=true
    fi

    # Find all Dockerfile.* variants in image directory
    # Use find to scan only top-level files, exclude templates and backups
    while IFS= read -r dockerfile_path; do
        # Extract variant name from filename
        local filename
        filename=$(basename "$dockerfile_path")

        # Skip Dockerfile itself (already added as default)
        if [[ "$filename" == "Dockerfile" ]]; then
            continue
        fi

        # Extract variant name from Dockerfile.{variant}
        local variant_name="${filename#Dockerfile.}"

        # Skip template files and backups
        if [[ "$variant_name" == "template" || "$variant_name" == "~" || "$variant_name" =~ ^.*~$ ]]; then
            continue
        fi

        # Validate variant name
        if ! validate_variant_name "$variant_name"; then
            log_warning "Skipping variant with invalid name: $variant_name (must be lowercase alphanumeric with hyphens and dots)"
            continue
        fi

        # Add variant to list
        variants+=("${variant_name}:${dockerfile_path}")
    done < <(find "$image_dir" -maxdepth 1 -name "Dockerfile*" -type f | sort)

    # Ensure at least one Dockerfile was found
    if [[ ${#variants[@]} -eq 0 ]]; then
        error "No Dockerfile or Dockerfile.* variants found in $image_dir"
        return 2
    fi

    # Build JSON array of variants
    # Default variant (if exists) is always first, then remaining variants alphabetically
    local json_variants='['
    local first=true

    for variant in "${variants[@]}"; do
        IFS=':' read -r name path <<< "$variant"

        if [[ "$first" == true ]]; then
            json_variants+="{\"name\":\"${name}\",\"dockerfile\":\"${path}\"}"
            first=false
        else
            json_variants+=",{\"name\":\"${name}\",\"dockerfile\":\"${path}\"}"
        fi
    done

    json_variants+=']'

    # Output JSON
    echo "{\"variants\":${json_variants}}"
}

#######################################
# Validates a variant name
#
# Checks that variant name is lowercase alphanumeric with optional hyphens and dots.
# Allows dots to support version-based variant names (e.g., act-24.04).
# Does not allow names that conflict with version strings.
#
# Arguments:
#   $1: Variant name to validate
#
# Returns:
#   0 if valid, 1 if invalid
#
#######################################
validate_variant_name() {
    local name="$1"

    # Empty name invalid
    if [[ -z "$name" ]]; then
        return 1
    fi

    # Must be lowercase alphanumeric with hyphens and dots
    # Dots are allowed to support version-based variants (e.g., act-24.04)
    if [[ ! "$name" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]]; then
        return 1
    fi

    # Reject consecutive hyphens (e.g., alpine--slim, test---variant)
    if [[ "$name" =~ -- ]]; then
        return 1
    fi

    # Cannot be "default" (reserved for main Dockerfile)
    if [[ "$name" == "default" ]]; then
        return 1
    fi

    return 0
}

#######################################
# Gets the absolute path to a Dockerfile for a variant
#
# Returns the absolute path to the Dockerfile for the given variant.
# For "default" variant, returns path to Dockerfile.
# For other variants, returns path to Dockerfile.{variant}.
#
# Arguments:
#   $1: Image directory
#   $2: Variant name
#
# Output (stdout):
#   Absolute path to Dockerfile
#
# Exit codes:
#   0: Success
#   1: Variant not found or invalid
#
#######################################
get_dockerfile_path() {
    local image_dir="$1"
    local variant="$2"

    if [[ -z "$image_dir" || -z "$variant" ]]; then
        error "Missing required arguments: image_dir and variant"
        return 1
    fi

    local dockerfile_path
    if [[ "$variant" == "default" ]]; then
        dockerfile_path="${image_dir}/Dockerfile"
    else
        dockerfile_path="${image_dir}/Dockerfile.${variant}"
    fi

    # Check file exists
    if [[ ! -f "$dockerfile_path" ]]; then
        error "Dockerfile not found for variant '$variant': $dockerfile_path"
        return 1
    fi

    echo "$dockerfile_path"
}
