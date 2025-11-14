#!/usr/bin/env bash
# Tag Builder Library
#
# Functions for generating Docker image tags for variants with support for
# multi-registry, multi-architecture tagging patterns.
#
# Usage:
#   source .github/scripts/lib/tag-builder.sh
#   build_variant_tags --image hello-world --version 1.0.0 --variant alpine --arch amd64
#   build_variant_tags --image hello-world --version 1.0.0 --variant default

set -euo pipefail

# Source logging library
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

#######################################
# Builds all tags for a specific variant build
#
# Generates both architecture-specific tags and manifest list tags.
# For default variant, omits variant suffix. For named variants, includes
# variant suffix in all tags.
#
# Tag patterns:
#   Architecture-specific:
#     - {version}-{variant}-{arch} (e.g., 1.0.0-alpine-amd64)
#     - {version}-{arch} (default variant only, e.g., 1.0.0-amd64)
#
#   Manifest list (without arch):
#     - {version}-{variant} (e.g., 1.0.0-alpine)
#     - {version} (default variant only, e.g., 1.0.0)
#     - {variant} (latest variant, e.g., alpine)
#     - latest (default variant only)
#     - latest-{variant} (e.g., latest-alpine)
#
# Arguments:
#   --image <name>      : Image name (required, e.g., hello-world)
#   --version <ver>     : Version string (required, e.g., 1.0.0)
#   --variant <var>     : Variant name (required, e.g., alpine or default)
#   --arch <arch>       : Architecture (optional, amd64/arm64; if provided, includes arch-specific tags)
#   --registry <reg>    : Registry prefix (optional, defaults to ghcr.io/username/repo)
#
# Output (stdout):
#   Newline-separated list of tags
#
# Exit codes:
#   0: Success
#   1: Missing required arguments or invalid inputs
#
#######################################
build_variant_tags() {
    local image_name=""
    local version=""
    local variant=""
    local arch=""
    local registry_prefix=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --image)
                image_name="$2"
                shift 2
                ;;
            --version)
                version="$2"
                shift 2
                ;;
            --variant)
                variant="$2"
                shift 2
                ;;
            --arch)
                arch="$2"
                shift 2
                ;;
            --registry)
                registry_prefix="$2"
                shift 2
                ;;
            *)
                log_error "Unknown argument: $1"
                return 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$image_name" ]]; then
        log_error "Missing required argument: --image"
        return 1
    fi

    if [[ -z "$version" ]]; then
        log_error "Missing required argument: --version"
        return 1
    fi

    # Validate version is not empty or whitespace-only
    if [[ "$version" =~ ^[[:space:]]*$ ]]; then
        log_error "Invalid version: empty or whitespace-only"
        return 1
    fi

    if [[ -z "$variant" ]]; then
        log_error "Missing required argument: --variant"
        return 1
    fi

    # Validate architecture if provided
    if [[ -n "$arch" ]]; then
        case "$arch" in
            amd64|arm64)
                # Valid architecture
                ;;
            *)
                log_error "Invalid architecture: $arch (must be amd64 or arm64)"
                return 1
                ;;
        esac
    fi

    # Set default registry prefix if not provided
    if [[ -z "$registry_prefix" ]]; then
        # Use GitHub registry as default
        # In GitHub Actions, this will be replaced with actual registry
        registry_prefix="ghcr.io/username/repo"
    fi

    local tags=()

    # Architecture-specific tags (if arch provided)
    if [[ -n "$arch" ]]; then
        if [[ "$variant" == "default" ]]; then
            # Default variant: version-arch (e.g., 1.0.0-amd64)
            tags+=("${registry_prefix}/${image_name}:${version}-${arch}")
        else
            # Named variant: version-variant-arch (e.g., 1.0.0-alpine-amd64)
            tags+=("${registry_prefix}/${image_name}:${version}-${variant}-${arch}")
        fi
    fi

    # Manifest list tags (shared between all architectures for same variant)
    if [[ "$variant" == "default" ]]; then
        # Default variant: omit variant suffix
        tags+=("${registry_prefix}/${image_name}:${version}")
        tags+=("${registry_prefix}/${image_name}:latest")
    else
        # Named variant: include variant suffix
        tags+=("${registry_prefix}/${image_name}:${version}-${variant}")
        tags+=("${registry_prefix}/${image_name}:${variant}")
        tags+=("${registry_prefix}/${image_name}:latest-${variant}")
    fi

    # Output all tags (one per line)
    printf '%s\n' "${tags[@]}"

    return 0
}

#######################################
# Validates a tag string format
#
# Ensures tag is Docker-compatible (alphanumeric, hyphens, dots, underscores,
# up to 128 characters)
#
# Arguments:
#   $1: Tag string to validate
#
# Returns:
#   0 if valid, 1 if invalid
#
#######################################
validate_tag() {
    local tag="$1"

    if [[ -z "$tag" ]]; then
        return 1
    fi

    # Docker tag rules: [a-zA-Z0-9_][a-zA-Z0-9._-]{0,127}
    # Simplified: alphanumeric, hyphens, dots, underscores, 1-128 chars
    if [[ ! "$tag" =~ ^[a-zA-Z0-9._-]{1,128}$ ]]; then
        return 1
    fi

    return 0
}
