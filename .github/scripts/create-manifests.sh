#!/usr/bin/env bash
# create-manifests.sh - Create multi-architecture Docker manifests for all built images
#
# Usage:
#   create-manifests.sh \
#     --repo REPO_NAME \
#     --commit COMMIT_SHA \
#     --branch BRANCH_NAME \
#     --digests-path PATH \
#     --status-path PATH \
#     --workspace PATH
#
# Description:
#   Processes digest and status artifacts from parallel builds to create unified
#   multi-architecture manifests. Handles commit tags, branch tags, and variant-specific tags.
#
# Exit Codes:
#   0 - Success (all manifests created)
#   1 - Fatal error
#
# Dependencies:
#   - merge-manifest.sh (manifest creation)
#   - tag-builder.sh (variant tag generation)
#   - bash 4.0+ (associative arrays)

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Global variables
REPO_NAME=""
COMMIT_SHA=""
BRANCH_NAME=""
DIGESTS_PATH="/tmp/digests"
STATUS_PATH="/tmp/status"
WORKSPACE="."

#######################################
# Print error message and exit
#######################################
error() {
  echo "ERROR: $1" >&2
  exit 1
}

#######################################
# Print warning message
#######################################
warn() {
  echo "WARNING: $1" >&2
}

#######################################
# Parse command-line arguments
#######################################
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        REPO_NAME="$2"
        shift 2
        ;;
      --commit)
        COMMIT_SHA="$2"
        shift 2
        ;;
      --branch)
        BRANCH_NAME="$2"
        shift 2
        ;;
      --digests-path)
        DIGESTS_PATH="$2"
        shift 2
        ;;
      --status-path)
        STATUS_PATH="$2"
        shift 2
        ;;
      --workspace)
        WORKSPACE="$2"
        shift 2
        ;;
      *)
        error "Unknown option: $1"
        ;;
    esac
  done

  # Validate required parameters
  [[ -z "$REPO_NAME" ]] && error "--repo is required"
  [[ -z "$COMMIT_SHA" ]] && error "--commit is required"
  [[ -z "$BRANCH_NAME" ]] && error "--branch is required"

  return 0
}

#######################################
# Create manifests for all image variants
#######################################
create_all_manifests() {
  # Source tag builder library for variant-specific tagging
  source "${SCRIPT_DIR}/lib/tag-builder.sh"

  # Repository name (lowercase required by Docker)
  local ghcr_repo
  ghcr_repo=$(echo "$REPO_NAME" | tr '[:upper:]' '[:lower:]')

  # Sanitize branch name for use as Docker tag
  local branch_tag
  branch_tag=$(echo "$BRANCH_NAME" | sed 's/[^a-zA-Z0-9.-]/-/g')

  echo "Creating multi-architecture manifests..."
  echo "========================================="

  # Build a map of unique (image, variant) pairs from digest artifacts
  # Artifact naming format: digest-{image}-{variant}-{arch}
  # We process all amd64 artifacts to get the list of (image, variant) pairs
  declare -A image_variant_pairs
  for amd64_artifact in "${DIGESTS_PATH}"/digest-*-amd64; do
    if [ -d "$amd64_artifact" ]; then
      local artifact_name
      artifact_name=$(basename "$amd64_artifact")

      # Extract everything except the -amd64 suffix
      # Pattern: digest-{image}-{variant}-amd64
      if [[ "$artifact_name" =~ ^digest-(.+)-amd64$ ]]; then
        # Remove 'digest-' prefix and '-amd64' suffix
        local image_variant="${BASH_REMATCH[1]}"

        # Validate image_variant is not empty (catch malformed artifact names)
        if [[ -z "$image_variant" ]]; then
          warn "Malformed artifact name (empty image-variant): $artifact_name"
          continue
        fi

        image_variant_pairs["$image_variant"]=1
      else
        # Regex did not match expected pattern
        warn "Artifact name does not match expected pattern: $artifact_name"
      fi
    fi
  done

  # If no artifacts found, exit gracefully
  if [ ${#image_variant_pairs[@]} -eq 0 ]; then
    echo "No digest artifacts found - build may have been skipped"
    exit 0
  fi

  # Process each unique (image, variant) pair
  for image_variant in "${!image_variant_pairs[@]}"; do
    # Collect digests and status for this (image, variant) pair
    local amd64_digest=""
    local arm64_digest=""
    local amd64_status="failure"
    local arm64_status="failure"

    # Read amd64 digest
    local amd64_artifact="${DIGESTS_PATH}/digest-${image_variant}-amd64/amd64.txt"
    if [ -f "$amd64_artifact" ]; then
      amd64_digest=$(cat "$amd64_artifact")
    fi

    # Read arm64 digest
    local arm64_artifact="${DIGESTS_PATH}/digest-${image_variant}-arm64/arm64.txt"
    if [ -f "$arm64_artifact" ]; then
      arm64_digest=$(cat "$arm64_artifact")
    fi

    # Read amd64 status
    local amd64_status_file="${STATUS_PATH}/status-${image_variant}-amd64/amd64.txt"
    if [ -f "$amd64_status_file" ]; then
      amd64_status=$(cat "$amd64_status_file")
    fi

    # Read arm64 status
    local arm64_status_file="${STATUS_PATH}/status-${image_variant}-arm64/arm64.txt"
    if [ -f "$arm64_status_file" ]; then
      arm64_status=$(cat "$arm64_status_file")
    fi

    # Parse image and variant from the combined name
    # Artifact format: digest-{image_with_underscores}-{variant}-{arch}
    # Image names with / are escaped to _ (e.g., traefik/traefik → traefik_traefik)
    local image_name=""
    local variant_name=""

    # Strategy: Try to match the artifact name against discovered images
    # We need to handle both flat (hello-world) and nested (traefik/traefik) structures

    # First, try exact underscore-to-slash conversion
    # Look for last occurrence of a valid image directory
    local test_image_variant="$image_variant"

    # Try progressively shorter prefixes as potential image names
    # Start with the full image_variant, then remove variant suffixes
    while [[ -n "$test_image_variant" ]]; do
      # Convert underscores to slashes for testing
      local test_image_path="${test_image_variant//_//}"

      # Check if this corresponds to an actual image directory
      if [ -d "${WORKSPACE}/${test_image_path}" ] && [ -f "${WORKSPACE}/${test_image_path}/metadata.yaml" ]; then
        image_name="$test_image_path"

        # Everything after image name is variant
        local remaining="${image_variant#${test_image_variant}}"
        if [[ "$remaining" == "-"* ]]; then
          variant_name="${remaining#-}"
        else
          variant_name="default"
        fi
        break
      fi

      # Try removing the last component (potential variant)
      if [[ "$test_image_variant" =~ ^(.+)-[^-]+$ ]]; then
        test_image_variant="${BASH_REMATCH[1]}"
      else
        break
      fi
    done

    # Error handling: No matching image directory found
    if [ -z "$image_name" ]; then
      error "Could not find matching image directory for artifact: $image_variant (tried converting _ to /)"
    fi

    # Determine registry path (support registry_path override from metadata.yaml)
    local registry_path=""
    local metadata_file="${WORKSPACE}/${image_name}/metadata.yaml"

    if [ -f "$metadata_file" ]; then
      # Check for registry_path override in metadata.yaml
      registry_path=$(yq eval '.registry_path // ""' "$metadata_file" 2>/dev/null || echo "")
    fi

    # Build image repository URL
    local image_repo
    if [ -n "$registry_path" ]; then
      # Use registry_path override (just owner namespace, not full repo path)
      local owner="${ghcr_repo%%/*}"
      image_repo="ghcr.io/${owner}/${registry_path}"
    else
      # Default: use repository name and image path
      image_repo="ghcr.io/${ghcr_repo}/${image_name}"
    fi

    echo ""
    echo "Processing: ${image_name} (variant: ${variant_name})"
    echo "  amd64: ${amd64_status} (${amd64_digest:0:12}...)"
    echo "  arm64: ${arm64_status} (${arm64_digest:0:12}...)"

    # Build common manifest args
    local manifest_args=(
      --image "${image_repo}"
      --amd64-digest "${amd64_digest}"
      --amd64-status "${amd64_status}"
      --arm64-digest "${arm64_digest}"
      --arm64-status "${arm64_status}"
      --verify
    )

    # Create manifest for commit SHA tag
    echo "Creating manifest for ${image_repo}:${COMMIT_SHA}..."
    "${SCRIPT_DIR}/merge-manifest.sh" \
      --tag "${COMMIT_SHA}" \
      "${manifest_args[@]}"

    # Create manifest for branch name tag
    echo "Creating manifest for ${image_repo}:${branch_tag}..."
    "${SCRIPT_DIR}/merge-manifest.sh" \
      --tag "${branch_tag}" \
      "${manifest_args[@]}"

    # Generate variant-specific tags using tag-builder.sh
    if [ "$variant_name" != "default" ]; then
      echo "Generating variant-specific tags for ${variant_name}..."

      # Extract version from one of the successful builds
      local version=""
      if [ -n "$amd64_digest" ] || [ -n "$arm64_digest" ]; then
        # Extract version from image metadata if available
        # Look for version in the image's metadata.yaml
        local version_file="${WORKSPACE}/${image_name}/metadata.yaml"
        if [ -f "$version_file" ]; then
          version=$(grep -oP '(?<=version:)[^,}]*' "$version_file" | head -1 | xargs 2>/dev/null || echo "")
        fi

        # Fallback: if version not found, use git commit hash as version
        if [ -z "$version" ]; then
          version="${COMMIT_SHA:0:8}"
        fi

        # Read tag strategy from metadata.yaml if present
        local tag_strategy=""
        if [ -f "$version_file" ]; then
          tag_strategy=$(yq eval '.tags.strategy // ""' "$version_file" 2>/dev/null || echo "")
        fi

        # Generate variant-specific tags
        local variant_tags
        if [ -n "$tag_strategy" ]; then
          variant_tags=$(build_variant_tags --image "$image_name" --version "$version" --variant "$variant_name" --registry "ghcr.io/${ghcr_repo}" --tag-strategy "$tag_strategy")
        else
          variant_tags=$(build_variant_tags --image "$image_name" --version "$version" --variant "$variant_name" --registry "ghcr.io/${ghcr_repo}")
        fi

        if [ -n "$variant_tags" ]; then
          echo "Generated tags for ${variant_name}:"
          echo "$variant_tags" | while read -r tag; do
            echo "  - $tag"
          done

          # Create manifest for variant-specific tags using merge-manifest.sh
          # Process each variant-specific tag
          echo "$variant_tags" | while read -r tag; do
            # Extract just the tag portion (after the last colon)
            local tag_value="${tag##*:}"

            echo "Creating manifest for variant tag: ${tag}..."
            "${SCRIPT_DIR}/merge-manifest.sh" \
              --tag "${tag_value}" \
              "${manifest_args[@]}" || {
              warn "Failed to create manifest for variant tag: ${tag}"
            }
          done
        else
          warn "Failed to generate variant-specific tags for ${variant_name}"
        fi
      fi
    fi
  done

  echo ""
  echo "Manifest creation complete"
  return 0
}

#######################################
# Main execution
#######################################
main() {
  parse_args "$@"
  create_all_manifests
  exit 0
}

# Run main function
main "$@"
