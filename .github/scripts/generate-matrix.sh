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
                log_error "Unknown option: $1"
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
        log_error "git is required but not found"
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
            # Force rebuild: include with force_rebuild reason
            # Check for version override (Sprint 13)
            local override_version
            override_version=$(get_version_override "$image_name" "$VERSION_OVERRIDE")
            local rebuild_version="${override_version:-}"
            local rebuild_reason="force_rebuild"
            if [[ -n "$override_version" ]]; then
                rebuild_reason="force_rebuild_with_version_override"
            fi

            local entry
            entry=$(matrix_create_entry "$image_name" "$rebuild_version" "$rebuild_reason") || {
                matrix_log_decision "$image_name" "$rebuild_version" "force_rebuild_create_error" "false"
                ((failed_count++))
                continue
            }
            # Verify entry is not empty (fallback for jq failures)
            if [[ -z "$entry" ]]; then
                matrix_log_error "matrix_create_entry produced no output for $image_name" "Skipping image"
                ((failed_count++))
                continue
            fi
            # Expand variants (Sprint 11a)
            while IFS= read -r variant_entry; do
                [[ -z "$variant_entry" ]] && continue
                matrix_entries+=("$variant_entry")
            done < <(expand_entry_with_variants "$entry" "$image_dir")
            matrix_log_decision "$image_name" "" "force_rebuild" "true"
            ((included_count++))
            continue
        fi

        # Call should_build_image() from Sprint 4b
        # This function determines if the image needs building based on version history and file changes
        # Note: Version detection is handled separately in version-detection workflow
        # For now, pass empty version and let should_build_image handle it
        local build_decision
        local error_output
        error_output=$(mktemp) || {
            matrix_log_error "Failed to create temp file for error capture"
            ((failed_count++))
            continue
        }

        # Capture build decision with error output to temp file
        if ! build_decision=$(should_build_image "$image_name" "$REPO_ROOT" "" 2>"$error_output"); then
            # Capture actual error from should_build_image
            local error_msg
            error_msg=$(cat "$error_output" 2>/dev/null || echo "Unknown error")
            rm -f "$error_output"

            # Log error with context
            matrix_log_error "should_build_image failed for $image_name: $error_msg" "Including in matrix as safety fallback"
            matrix_log_decision "$image_name" "" "build_decision_error" "true"

            local entry
            entry=$(matrix_create_entry "$image_name" "" "version_detection_failed") || {
                ((failed_count++))
                continue
            }
            # Expand variants (Sprint 11a)
            while IFS= read -r variant_entry; do
                [[ -z "$variant_entry" ]] && continue
                matrix_entries+=("$variant_entry")
            done < <(expand_entry_with_variants "$entry" "$image_dir")
            ((included_count++))
            continue
        fi

        # Cleanup temp file after successful read
        rm -f "$error_output"

        # Parse build decision JSON
        # Expected format: {"image_name":"...","should_build":true/false,"reason":"...","version":"..."}
        local should_build
        should_build=$(echo "$build_decision" | jq -r '.should_build // false' 2>/dev/null)
        local version
        version=$(echo "$build_decision" | jq -r '.version // ""' 2>/dev/null)
        local reason
        reason=$(echo "$build_decision" | jq -r '.reason // "unknown"' 2>/dev/null)

        if [[ "$should_build" == "true" ]]; then
            # Include image in matrix
            # Check for version override (Sprint 13)
            local override_version
            override_version=$(get_version_override "$image_name" "$VERSION_OVERRIDE")
            if [[ -n "$override_version" ]]; then
                version="$override_version"
                reason="version_override"
            fi

            # Detect supported architectures (Sprint 14)
            local detected_archs="amd64 arm64"  # Conservative default
            if [[ "$ARCHITECTURE_DETECTION_AVAILABLE" == "true" ]]; then
                local detection_output
                if detection_output=$(detect_supported_architectures "$image_dir" 2>/dev/null); then
                    # Remove any trailing newlines from detection output
                    detected_archs=$(echo "$detection_output" | tr -d '\n' | xargs)
                    log_debug "Detected architectures for $image_name: $detected_archs"
                else
                    log_debug "Architecture detection failed for $image_name, using conservative default"
                    detected_archs="amd64 arm64"
                fi
            fi

            local entry
            entry=$(matrix_create_entry "$image_name" "$version" "$reason" "$detected_archs") || {
                matrix_log_decision "$image_name" "$version" "$reason" "false"
                ((failed_count++))
                continue
            }
            # Verify entry is not empty (fallback for jq failures)
            if [[ -z "$entry" ]]; then
                matrix_log_error "matrix_create_entry produced no output for $image_name" "Skipping image"
                ((failed_count++))
                continue
            fi
            # Expand variants (Sprint 11a)
            while IFS= read -r variant_entry; do
                [[ -z "$variant_entry" ]] && continue
                matrix_entries+=("$variant_entry")
            done < <(expand_entry_with_variants "$entry" "$image_dir")
            matrix_log_decision "$image_name" "$version" "$reason" "true"
            ((included_count++))
        else
            # Skip image
            matrix_log_decision "$image_name" "$version" "$reason" "false"
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
            log_error "Failed to set GitHub Actions output"
            return 1
        fi
    fi

    return 0
}

# ============================================================================
# Fallback: Build all images (safe default on critical errors)
# ============================================================================

generate_fallback_matrix() {
    log_error "Matrix generation failed - falling back to building all images"

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
