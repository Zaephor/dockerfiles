#!/usr/bin/env bash
# Dynamic matrix generation for GitHub Actions conditional builds
# Discovers all images and determines which need building based on changes and version history
#
# This script integrates Sprint 4b conditional build logic with GitHub Actions workflow orchestration
#
# Usage:
#   generate-matrix.sh [--repo-root REPO_ROOT] [--force-rebuild IMAGES]
#
# Parameters:
#   --repo-root: Repository root path (optional, defaults to current directory)
#   --force-rebuild: Comma-separated image names or "all" (optional)
#
# Output:
#   JSON matrix to stdout in GitHub Actions format: {"image":[...]}
#   Sets GITHUB_OUTPUT matrix variable if GITHUB_OUTPUT is defined
#
# Exit codes:
#   0: Success (matrix generated, even if empty)
#   1: Error (falls back to building all images)

set -o pipefail

# ============================================================================
# Configuration
# ============================================================================

REPO_ROOT="${REPO_ROOT:-.}"
FORCE_REBUILD="${FORCE_REBUILD:-}"
IMAGE_FILTER="${IMAGE_FILTER:-}"
SKIP_IMAGES="${SKIP_IMAGES:-}"
VERSION_OVERRIDE="${VERSION_OVERRIDE:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# Load dependencies
# ============================================================================

# Source logging library FIRST (required by all other libraries)
if [[ ! -f "$SCRIPT_DIR/lib/logging.sh" ]]; then
    echo "ERROR: logging.sh not found at $SCRIPT_DIR/lib/logging.sh" >&2
    exit 1
fi
source "$SCRIPT_DIR/lib/logging.sh"

# Source matrix utilities (depends on jq, no logging dependencies)
if [[ ! -f "$SCRIPT_DIR/lib/matrix-utils.sh" ]]; then
    echo "ERROR: matrix-utils.sh not found at $SCRIPT_DIR/lib/matrix-utils.sh" >&2
    exit 1
fi
source "$SCRIPT_DIR/lib/matrix-utils.sh"

# Source image discovery utilities
if [[ ! -f "$SCRIPT_DIR/lib/image-discovery.sh" ]]; then
    echo "ERROR: image-discovery.sh not found at $SCRIPT_DIR/lib/image-discovery.sh" >&2
    exit 1
fi
source "$SCRIPT_DIR/lib/image-discovery.sh"

# Source conditional builds (depends on logging.sh via conditional-builds-utils.sh)
if [[ ! -f "$SCRIPT_DIR/conditional-builds.sh" ]]; then
    echo "ERROR: conditional-builds.sh not found at $SCRIPT_DIR/conditional-builds.sh" >&2
    exit 1
fi
source "$SCRIPT_DIR/conditional-builds.sh"

# Source variant discovery library (optional, added in Sprint 11a)
if [[ -f "$SCRIPT_DIR/lib/variant-discovery.sh" ]]; then
    source "$SCRIPT_DIR/lib/variant-discovery.sh"
    VARIANT_DISCOVERY_AVAILABLE=true
else
    VARIANT_DISCOVERY_AVAILABLE=false
fi

# Source architecture detection library (Sprint 14)
if [[ -f "$SCRIPT_DIR/lib/architecture-detection.sh" ]]; then
    source "$SCRIPT_DIR/lib/architecture-detection.sh"
    ARCHITECTURE_DETECTION_AVAILABLE=true
else
    ARCHITECTURE_DETECTION_AVAILABLE=false
    log_warn "architecture-detection.sh not found - architecture auto-detection unavailable"
fi

# ============================================================================
# Argument parsing
# ============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo-root)
                shift
                REPO_ROOT="$1"
                ;;
            --force-rebuild)
                shift
                FORCE_REBUILD="$1"
                ;;
            --image-filter)
                shift
                IMAGE_FILTER="$1"
                ;;
            --skip-images)
                shift
                SKIP_IMAGES="$1"
                ;;
            --version-override)
                shift
                VERSION_OVERRIDE="$1"
                ;;
            *)
                error "Unknown option: $1"
                return 1
                ;;
        esac
        shift
    done

    return 0
}

# ============================================================================
# Validation
# ============================================================================

validate_tools() {
    if ! matrix_validate_tools; then
        return 1
    fi

    if ! command -v git &>/dev/null; then
        error "git is required but not found"
        return 1
    fi

    return 0
}

# ============================================================================
# Force rebuild parsing
# ============================================================================

# Parses the force-rebuild parameter and returns a map of images to force rebuild
# Returns: space-separated image names (or "all")
parse_force_rebuild() {
    local force_rebuild="$1"

    if [[ -z "$force_rebuild" ]]; then
        echo ""
        return 0
    fi

    # Normalize to lowercase for comparison
    local normalized
    normalized=$(echo "$force_rebuild" | tr '[:upper:]' '[:lower:]')

    if [[ "$normalized" == "all" ]]; then
        echo "all"
    else
        # Return comma-separated list (will be parsed later)
        echo "$force_rebuild"
    fi

    return 0
}

# Checks if an image should be force-rebuilt
# Parameters:
#   IMAGE_NAME: Name of the image to check
#   FORCE_REBUILD_LIST: Space or comma-separated list of images or "all"
# Returns:
#   0 if image should be force rebuilt
#   1 otherwise
should_force_rebuild() {
    local image_name="$1"
    local force_rebuild_list="$2"

    if [[ -z "$force_rebuild_list" ]]; then
        return 1
    fi

    # "all" means force rebuild everything
    if [[ "$force_rebuild_list" == "all" ]]; then
        return 0
    fi

    # Check if image is in comma-separated list
    if echo "$force_rebuild_list" | grep -q "$(echo "$image_name" | sed 's/[]\/$*.^[]/\\&/g')"; then
        return 0
    fi

    return 1
}

# should_include_image: Check if image passes image_filter filter (includes if in list or list is empty)
#
# Returns:
#   0 (true) if image should be included based on filter
#   1 (false) if image is excluded by filter
#
should_include_image() {
    local image_name="$1"
    local image_filter="$2"

    # No filter means include all
    if [[ -z "$image_filter" ]]; then
        return 0
    fi

    # Check if image is in comma-separated include list
    if echo "$image_filter" | grep -q "$(echo "$image_name" | sed 's/[]\/$*.^[]/\\&/g')"; then
        return 0
    fi

    return 1
}

# should_skip_image: Check if image is in skip list
#
# Returns:
#   0 (true) if image should be skipped
#   1 (false) if image should not be skipped
#
should_skip_image() {
    local image_name="$1"
    local skip_list="$2"

    # No skip list means skip nothing
    if [[ -z "$skip_list" ]]; then
        return 1
    fi

    # Check if image is in comma-separated skip list
    if echo "$skip_list" | grep -q "$(echo "$image_name" | sed 's/[]\/$*.^[]/\\&/g')"; then
        return 0
    fi

    return 1
}

# get_version_override: Extract version override for specific image
#
# Arguments:
#   IMAGE_NAME: Image to look up
#   VERSION_OVERRIDE_STRING: Override string in format "image1=v1.0,image2=v2.0"
#
# Returns:
#   Override version if found, empty string otherwise
#
get_version_override() {
    local image_name="$1"
    local override_string="$2"

    # No overrides configured
    if [[ -z "$override_string" ]]; then
        echo ""
        return
    fi

    # Parse comma-separated key=value pairs
    while IFS='=' read -r override_image override_version; do
        # Trim whitespace
        override_image=$(echo "$override_image" | xargs)
        override_version=$(echo "$override_version" | xargs)

        if [[ "$override_image" == "$image_name" ]]; then
            echo "$override_version"
            return
        fi
    done <<< "$(echo "$override_string" | sed 's/,/\n/g')"

    # No override found for this image
    echo ""
}

# ============================================================================
# Variant expansion functions (Sprint 11a)
# ============================================================================

# Expands a matrix entry to include variants if variant discovery is available
# If variant discovery is disabled, returns a single entry with Dockerfile path
# Parameters:
#   $1: Matrix entry JSON (from matrix_create_entry)
#   $2: Image directory path
# Returns:
#   JSON object(s) to stdout with variant and dockerfile fields added
expand_entry_with_variants() {
    local entry="$1"
    local image_dir="$2"

    if [[ ! "$VARIANT_DISCOVERY_AVAILABLE" == "true" ]]; then
        # Variant discovery not available - just add default Dockerfile path
        echo "$entry" | jq --arg dockerfile "${image_dir}/Dockerfile" '. + {variant: "default", dockerfile: $dockerfile}' 2>/dev/null
        return 0
    fi

    # Discover variants for this image
    local variants_json
    if ! variants_json=$(discover_variants --image-dir "$image_dir" 2>/dev/null); then
        # Discovery failed - fallback to default variant
        echo "$entry" | jq --arg dockerfile "${image_dir}/Dockerfile" '. + {variant: "default", dockerfile: $dockerfile}' 2>/dev/null
        return 0
    fi

    # Validate JSON structure - ensure variants field exists
    if ! echo "$variants_json" | jq -e '.variants' >/dev/null 2>&1; then
        # Invalid JSON structure - fallback to default variant
        echo "$entry" | jq --arg dockerfile "${image_dir}/Dockerfile" '. + {variant: "default", dockerfile: $dockerfile}' 2>/dev/null
        return 0
    fi

    # Extract variant list and expand entry for each
    local variant_count
    variant_count=$(echo "$variants_json" | jq '.variants | length' 2>/dev/null)

    if [[ -z "$variant_count" || "$variant_count" -eq 0 ]]; then
        # No variants found - use default
        echo "$entry" | jq --arg dockerfile "${image_dir}/Dockerfile" '. + {variant: "default", dockerfile: $dockerfile}' 2>/dev/null
        return 0
    fi

    # For each variant, output a copy of the entry with variant and dockerfile fields
    echo "$variants_json" | jq -c ".variants[] | {name: .name, dockerfile: .dockerfile}" 2>/dev/null | while read -r variant_obj; do
        local variant_name
        local dockerfile
        variant_name=$(echo "$variant_obj" | jq -r '.name' 2>/dev/null)
        dockerfile=$(echo "$variant_obj" | jq -r '.dockerfile' 2>/dev/null)

        # Output expanded entry
        echo "$entry" | jq --arg variant "$variant_name" --arg dockerfile "$dockerfile" '. + {variant: $variant, dockerfile: $dockerfile}' 2>/dev/null
    done

    return 0
}

# Process an image with per-variant version detection and build decisions
# Parameters:
#   $1: Image name
#   $2: Image directory path
#   $3: Force rebuild (true/false)
#   $4: Version override (optional)
# Returns:
#   Outputs matrix entries (one per variant that should build) to stdout
#   Returns 0 if any variants processed, 1 on error
process_image_variants() {
    local image_name="$1"
    local image_dir="$2"
    local force_rebuild="$3"
    local version_override="${4:-}"

    local config_file="${image_dir}/metadata.yaml"
    local has_entries=false

    # Discover variants for this image
    local variants_json
    if [[ ! "$VARIANT_DISCOVERY_AVAILABLE" == "true" ]]; then
        # Variant discovery not available - use default variant
        variants_json='{"variants":[{"name":"default","dockerfile":"'${image_dir}'/Dockerfile"}]}'
    elif ! variants_json=$(discover_variants --image-dir "$image_dir" 2>/dev/null); then
        # Discovery failed - fallback to default variant
        variants_json='{"variants":[{"name":"default","dockerfile":"'${image_dir}'/Dockerfile"}]}'
    fi

    # Process each variant independently
    echo "$variants_json" | jq -c '.variants[]' 2>/dev/null | while read -r variant_obj; do
        local variant_name variant_dockerfile
        variant_name=$(echo "$variant_obj" | jq -r '.name' 2>/dev/null)
        variant_dockerfile=$(echo "$variant_obj" | jq -r '.dockerfile' 2>/dev/null)

        # Detect version for THIS variant
        local detected_version=""
        if [[ -f "$config_file" ]]; then
            local version_result
            if version_result=$("${REPO_ROOT}/.github/scripts/version-detection.sh" --config "$config_file" --image-name "$image_name" --variant "$variant_name" 2>/dev/null); then
                detected_version=$(echo "$version_result" | jq -r '.version // ""' 2>/dev/null || echo "")
            fi
        fi

        # Make build decision for THIS variant
        local should_build="false"
        local build_reason="unknown"
        local build_version="$detected_version"

        if [[ "$force_rebuild" == "true" ]]; then
            should_build="true"
            build_reason="force_rebuild"
            if [[ -n "$version_override" ]]; then
                build_version="$version_override"
                build_reason="force_rebuild_with_version_override"
            fi
        else
            # Call should_build_image with variant parameter
            local build_decision
            if build_decision=$(should_build_image "$image_name" "$REPO_ROOT" "$detected_version" "$variant_name" 2>/dev/null); then
                should_build=$(echo "$build_decision" | jq -r '.should_build // false' 2>/dev/null)
                build_version=$(echo "$build_decision" | jq -r '.version // ""' 2>/dev/null)
                build_reason=$(echo "$build_decision" | jq -r '.reason // "unknown"' 2>/dev/null)
            else
                # Build decision failed - include as safety fallback
                should_build="true"
                build_reason="build_decision_error"
            fi
        fi

        # If should build, detect architectures and create matrix entry
        if [[ "$should_build" == "true" ]]; then
            # Log variant decision (INCLUDE)
            matrix_log_decision "$image_name" "$build_version" "$build_reason" "true" "$variant_name"

            # Detect supported architectures
            local detected_archs="amd64 arm64"  # Conservative default
            if [[ "$ARCHITECTURE_DETECTION_AVAILABLE" == "true" ]]; then
                local detection_output
                if detection_output=$(detect_supported_architectures "$image_dir" 2>/dev/null); then
                    detected_archs=$(echo "$detection_output" | tr -d '\n' | xargs)
                fi
            fi

            local entry
            entry=$(matrix_create_entry "$image_name" "$build_version" "$build_reason" "$detected_archs") || continue

            # Add variant and dockerfile to entry
            entry=$(echo "$entry" | jq --arg variant "$variant_name" --arg dockerfile "$variant_dockerfile" \
                '. + {variant: $variant, dockerfile: $dockerfile}' 2>/dev/null)

            if [[ -n "$entry" ]]; then
                echo "$entry"
                has_entries=true
            fi
        else
            # Log variant decision (SKIP)
            matrix_log_decision "$image_name" "$build_version" "$build_reason" "false" "$variant_name"
        fi
    done

    # Return success if any entries were output
    if [[ "$has_entries" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# Main matrix generation logic
# ============================================================================

generate_matrix() {
    # Validate environment
    if ! validate_tools; then
        matrix_log_error "Required tools not available" "Building all images (safe fallback)"
        return 1
    fi

    # Discover image directories
    local images
    if ! images=$(discover_image_directories "$REPO_ROOT"); then
        matrix_log_error "Failed to discover images" "Building all images (safe fallback)"
        return 1
    fi

    # Count images
    local image_count=0
    if [[ -n "$images" ]]; then
        image_count=$(echo "$images" | wc -l)
    fi

    matrix_log_start "$image_count"

    # Parse force rebuild parameter
    local force_rebuild_list
    if ! force_rebuild_list=$(parse_force_rebuild "$FORCE_REBUILD"); then
        matrix_log_error "Invalid force-rebuild parameter" "Building all images (safe fallback)"
        return 1
    fi

    # Track results
    local matrix_entries=()
    local included_count=0
    local failed_count=0

    # Process each image
    while IFS= read -r image_name; do
        [[ -z "$image_name" ]] && continue

        # Verify image directory structure
        local image_dir="$REPO_ROOT/$image_name"
        if ! verify_image_directory "$image_dir"; then
            matrix_log_decision "$image_name" "" "invalid_directory" "false"
            ((failed_count++))
            continue
        fi

        # Apply manual filters (Sprint 13)
        # Check image_filter: if set, only include matching images
        if ! should_include_image "$image_name" "$IMAGE_FILTER"; then
            matrix_log_decision "$image_name" "" "filtered_out" "false"
            continue
        fi

        # Check skip_images: exclude these (unless force_rebuild overrides)
        if should_skip_image "$image_name" "$SKIP_IMAGES"; then
            # Check if force_rebuild overrides skip
            if should_force_rebuild "$image_name" "$force_rebuild_list"; then
                # Force rebuild overrides skip - continue to force rebuild logic below
                matrix_log_decision "$image_name" "" "skip_overridden_by_force" "true"
            else
                matrix_log_decision "$image_name" "" "skipped" "false"
                continue
            fi
        fi

        # Check if this image should be force-rebuilt
        if should_force_rebuild "$image_name" "$force_rebuild_list"; then
            # Force rebuild: process all variants
            local override_version
            override_version=$(get_version_override "$image_name" "$VERSION_OVERRIDE")

            # Process variants with force rebuild enabled
            while IFS= read -r variant_entry; do
                [[ -z "$variant_entry" ]] && continue
                matrix_entries+=("$variant_entry")
                ((included_count++))
            done < <(process_image_variants "$image_name" "$image_dir" "true" "$override_version")

            matrix_log_decision "$image_name" "" "force_rebuild" "true"
            continue
        fi

        # Process all variants for this image with per-variant version detection
        local override_version
        override_version=$(get_version_override "$image_name" "$VERSION_OVERRIDE")

        local variant_count=0
        while IFS= read -r variant_entry; do
            [[ -z "$variant_entry" ]] && continue
            matrix_entries+=("$variant_entry")
            ((variant_count++))
        done < <(process_image_variants "$image_name" "$image_dir" "false" "$override_version")

        # Track if any variants were included (per-variant decisions already logged)
        if [[ $variant_count -gt 0 ]]; then
            ((included_count++))
        fi
    done <<<"$images"

    # Build final matrix JSON
    local matrix_json
    if [[ ${#matrix_entries[@]} -eq 0 ]]; then
        # No images to build - return empty matrix
        matrix_json=$(matrix_create_empty)
    else
        # Build matrix from entries
        if ! matrix_json=$(printf '%s\n' "${matrix_entries[@]}" | matrix_build_json); then
            matrix_log_error "Failed to build matrix JSON" "Building all images (safe fallback)"
            return 1
        fi
    fi

    # Log completion
    matrix_log_complete "$included_count" "$image_count"

    # Output matrix
    echo "$matrix_json"

    # Set GitHub Actions output if in CI environment
    if [[ -n "$GITHUB_OUTPUT" ]]; then
        if ! matrix_set_output "matrix" "$matrix_json"; then
            error "Failed to set GitHub Actions output"
            return 1
        fi
    fi

    return 0
}

# ============================================================================
# Fallback: Build all images (safe default on critical errors)
# ============================================================================

generate_fallback_matrix() {
    error "Matrix generation failed - falling back to building all images"

    # Discover images for fallback
    local images
    images=$(discover_image_directories "$REPO_ROOT") || {
        # Cannot even discover images - return empty matrix
        # (better to skip than build with wrong images)
        echo '{"image":[]}'
        return 1
    }

    # Build matrix with all images
    local matrix_entries=()
    while IFS= read -r image_name; do
        [[ -z "$image_name" ]] && continue
        local entry
        entry=$(matrix_create_entry "$image_name" "" "fallback_build_all") || continue
        matrix_entries+=("$entry")
    done <<<"$images"

    if [[ ${#matrix_entries[@]} -eq 0 ]]; then
        echo '{"image":[]}'
    else
        printf '%s\n' "${matrix_entries[@]}" | matrix_build_json
    fi

    return 1
}

# ============================================================================
# Main entry point
# ============================================================================

main() {
    # Parse arguments
    if ! parse_arguments "$@"; then
        return 1
    fi

    # Generate matrix
    if ! generate_matrix; then
        # On critical error, fall back to building all images
        generate_fallback_matrix
        return 1
    fi

    return 0
}

main "$@"
exit $?
