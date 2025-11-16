#!/usr/bin/env bash

# Architecture Detection Library
# Automatically detects which architectures (amd64, arm64) are supported by upstream sources
# Implements Constitution Principle 1: Auto-Detection Over Configuration
# Implements Constitution Principle 2: Architecture Normalization and Graceful Degradation

set -o pipefail

# Note: Logging library should be sourced by the calling script before sourcing this library
# We assume log_debug, log_warn, log_error functions are already available

# Architecture validation list (per Constitution Principle 2)
readonly SUPPORTED_ARCHITECTURES=("amd64" "arm64")

# Logging fallbacks if not already defined
if ! declare -F log_debug >/dev/null 2>&1; then
  log_debug() { echo "[DEBUG] $*" >&2; }
fi
if ! declare -F log_warn >/dev/null 2>&1; then
  log_warn() { echo "[WARN] $*" >&2; }
fi
if ! declare -F error >/dev/null 2>&1; then
  error() { echo "[ERROR] $*" >&2; }
fi
if ! declare -F log_error >/dev/null 2>&1; then
  log_error() { echo "[ERROR] $*" >&2; }
fi

# ==============================================================================
# Utility Functions
# ==============================================================================

# Normalize architecture names to standard format
# Uses Sprint 6 architecture normalization patterns
normalize_architecture() {
  local arch="$1"

  case "${arch,,}" in
    amd64|x86-64|x86_64|x64)
      echo "amd64"
      ;;
    arm64|aarch64|armv8)
      echo "arm64"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

# Validate architecture configuration against supported values
# Inputs: comma-separated or space-separated list of architectures
# Returns: 0 if valid, 1 if invalid
validate_architecture_config() {
  local config="$1"
  local arch_list=()

  # Parse comma or space-separated list
  if [[ "$config" == *","* ]]; then
    IFS=',' read -ra arch_list <<<"$config"
  else
    IFS=' ' read -ra arch_list <<<"$config"
  fi

  # Remove whitespace and validate each
  for arch in "${arch_list[@]}"; do
    arch="${arch// /}"  # trim whitespace

    if [[ -z "$arch" ]]; then
      continue
    fi

    # Check if architecture is supported
    local found=0
    for supported in "${SUPPORTED_ARCHITECTURES[@]}"; do
      if [[ "$arch" == "$supported" ]]; then
        found=1
        break
      fi
    done

    if [[ $found -eq 0 ]]; then
      echo "ERROR: Invalid architecture '$arch'. Supported: ${SUPPORTED_ARCHITECTURES[*]}" >&2
      return 1
    fi
  done

  return 0
}

# ==============================================================================
# Detection Methods (Placeholders - implemented in next phases)
# ==============================================================================

# Detect architectures from base image manifest
# Inputs: base_image (e.g., ubuntu:22.04)
# Returns: space-separated list of architectures (amd64 arm64)
detect_from_base_image_manifest() {
  local base_image="$1"
  local detected_archs=()

  if [[ -z "$base_image" ]]; then
    log_debug "Empty base image provided to detect_from_base_image_manifest"
    return 1
  fi

  log_debug "Querying manifest for base image: $base_image"

  # Use docker buildx imagetools inspect to query manifest
  # This handles authentication automatically and works with all registries
  local manifest_output
  if ! manifest_output=$(docker buildx imagetools inspect --raw "$base_image" 2>/dev/null); then
    log_debug "Failed to query manifest for $base_image (image may not exist or be multi-arch)"
    return 1
  fi

  # Parse manifest to extract architectures
  # Handle both manifest lists (multi-arch) and single manifests
  local arch
  if echo "$manifest_output" | jq -e '.manifests' >/dev/null 2>&1; then
    # Multi-arch manifest list (Docker v2 schema 2)
    while IFS= read -r arch; do
      if [[ -n "$arch" && "$arch" != "null" ]]; then
        local normalized
        normalized=$(normalize_architecture "$arch")
        if [[ "$normalized" != "unknown" ]]; then
          detected_archs+=("$normalized")
        fi
      fi
    done < <(echo "$manifest_output" | jq -r '.manifests[]? | select(.platform.os == "linux") | .platform.architecture' 2>/dev/null)
  elif echo "$manifest_output" | jq -e '.architecture' >/dev/null 2>&1; then
    # Single-arch manifest (Docker v2 schema 1 or OCI image)
    arch=$(echo "$manifest_output" | jq -r '.architecture' 2>/dev/null)
    if [[ -n "$arch" && "$arch" != "null" ]]; then
      local normalized
      normalized=$(normalize_architecture "$arch")
      if [[ "$normalized" != "unknown" ]]; then
        detected_archs+=("$normalized")
      fi
    fi
  fi

  # Return detected architectures if any
  if [[ ${#detected_archs[@]} -gt 0 ]]; then
    normalize_architecture_list "${detected_archs[@]}"
    return 0
  fi

  log_debug "No supported architectures found in manifest for: $base_image"
  return 1
}

# Detect architectures from GitHub release assets
# Inputs: image_dir (path to image directory)
# Returns: space-separated list of architectures
detect_from_github_releases() {
  local image_dir="$1"
  local detected_archs=()

  if [[ ! -f "$image_dir/metadata.yaml" ]]; then
    log_debug "No metadata.yaml found in $image_dir"
    return 1
  fi

  # Extract version source from metadata.yaml
  local version_source
  version_source=$(yq -r '.version_source // empty' "$image_dir/metadata.yaml" 2>/dev/null)

  if [[ -z "$version_source" ]] || ! echo "$version_source" | grep -q "github"; then
    log_debug "No GitHub version source configured in $image_dir/metadata.yaml"
    return 1
  fi

  # Extract repository from version_source (e.g., "github_releases:owner/repo")
  local repo
  repo="${version_source##*:}"

  if [[ -z "$repo" ]]; then
    log_debug "Could not extract repository from version_source in $image_dir"
    return 1
  fi

  log_debug "Querying GitHub releases for: $repo"

  # Query GitHub API for latest release assets
  # Use GITHUB_TOKEN for authentication (available in CI, optional locally)
  local gh_api_args=()
  [[ -n "$GITHUB_TOKEN" ]] && gh_api_args+=(--header "authorization: Bearer $GITHUB_TOKEN")

  local release_data
  if ! release_data=$(curl -s "${gh_api_args[@]}" "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null); then
    log_debug "Failed to query GitHub API for $repo"
    return 1
  fi

  # Extract asset names from release
  local asset_name
  while IFS= read -r asset_name; do
    if [[ -z "$asset_name" ]]; then
      continue
    fi

    # Match architecture patterns in asset names (case-insensitive)
    local arch_match
    if arch_match=$(echo "${asset_name,,}" | grep -oE '(amd64|x86[_-]?64|x64|arm64|aarch64|armv8)' | head -1); then
      if [[ -n "$arch_match" ]]; then
        local normalized
        normalized=$(normalize_architecture "$arch_match")
        if [[ "$normalized" != "unknown" ]]; then
          detected_archs+=("$normalized")
        fi
      fi
    fi
  done < <(echo "$release_data" | jq -r '.assets[]?.name' 2>/dev/null)

  # Return detected architectures if any
  if [[ ${#detected_archs[@]} -gt 0 ]]; then
    normalize_architecture_list "${detected_archs[@]}"
    return 0
  fi

  log_debug "No architecture patterns found in GitHub release assets for $repo"
  return 1
}

# Detect architectures from download URLs
# Inputs: image_dir (path to image directory)
# Returns: space-separated list of architectures
detect_from_download_urls() {
  local image_dir="$1"
  local detected_archs=()

  if [[ ! -f "$image_dir/metadata.yaml" ]]; then
    log_debug "No metadata.yaml found in $image_dir"
    return 1
  fi

  # Extract download_url_template from metadata.yaml
  local url_template
  url_template=$(yq -r '.download_url_template // empty' "$image_dir/metadata.yaml" 2>/dev/null)

  if [[ -z "$url_template" ]]; then
    log_debug "No download_url_template configured in $image_dir/metadata.yaml"
    return 1
  fi

  # Extract version for URL substitution
  local version
  version=$(yq -r '.version // empty' "$image_dir/metadata.yaml" 2>/dev/null)

  if [[ -z "$version" ]]; then
    log_debug "No version available for URL template in $image_dir"
    return 1
  fi

  log_debug "Testing download URLs with template: $url_template"

  # Test each architecture
  for arch in amd64 arm64; do
    local test_url
    test_url="${url_template//\{arch\}/$arch}"
    test_url="${test_url//\{version\}/$version}"

    if [[ "$test_url" == "$url_template" ]]; then
      # Template has no {arch} or {version} placeholders
      log_debug "URL template contains no architecture placeholders: $url_template"
      return 1
    fi

    log_debug "Testing URL: $test_url"

    # Use curl HEAD request to check if URL exists (10 second timeout)
    if curl -I --silent --fail --max-time 10 "$test_url" >/dev/null 2>&1; then
      log_debug "URL exists for $arch: $test_url"
      detected_archs+=("$arch")
    elif curl -r 0-0 --silent --fail --max-time 10 "$test_url" >/dev/null 2>&1; then
      # Fallback for CDNs that block HEAD requests
      log_debug "URL exists for $arch (via range request): $test_url"
      detected_archs+=("$arch")
    else
      log_debug "URL does not exist for $arch: $test_url"
    fi
  done

  # Return detected architectures if any
  if [[ ${#detected_archs[@]} -gt 0 ]]; then
    normalize_architecture_list "${detected_archs[@]}"
    return 0
  fi

  log_debug "No working download URLs found for any architecture"
  return 1
}

# Detect architectures from manual configuration in metadata.yaml
# Inputs: image_dir (path to image directory)
# Returns: space-separated list of architectures
detect_from_manual_config() {
  local image_dir="$1"
  local metadata_file="$image_dir/metadata.yaml"

  if [[ ! -f "$metadata_file" ]]; then
    log_debug "No metadata.yaml found in $image_dir"
    return 1
  fi

  # Check if architectures field exists in metadata.yaml
  if ! yq -e '.architectures' "$metadata_file" >/dev/null 2>&1; then
    log_debug "No architectures field in $metadata_file"
    return 1
  fi

  # Extract architectures array
  local archs_str
  archs_str=$(yq -r '.architectures | join(" ")' "$metadata_file" 2>/dev/null)

  if [[ -z "$archs_str" ]]; then
    log_debug "Empty architectures field in $metadata_file"
    return 1
  fi

  # Validate architecture configuration
  if ! validate_architecture_config "$archs_str" 2>/dev/null; then
    error "Invalid architecture configuration in $metadata_file: $archs_str"
    return 1
  fi

  log_debug "Using manual architecture configuration from $metadata_file: $archs_str"
  echo "$archs_str"
  return 0
}

# ==============================================================================
# Main Detection Function
# ==============================================================================

# Detect supported architectures with priority fallback chain
# Priority order:
#   1. Manual configuration (metadata.yaml)
#   2. Base image manifest
#   3. GitHub release binaries
#   4. Download URLs
#   5. Conservative default (amd64 + arm64)
#
# Inputs: image_dir (path to image directory)
# Outputs: space-separated list of architectures
# Stderr: detection method used
detect_supported_architectures() {
  local image_dir="$1"

  if [[ ! -d "$image_dir" ]]; then
    error "Image directory not found: $image_dir"
    return 1
  fi

  log_debug "Detecting supported architectures for: $image_dir"

  # Priority 1: Manual configuration
  if detect_from_manual_config "$image_dir" 2>/dev/null; then
    log_debug "Using manual configuration from metadata.yaml"
    echo "manual_config" >&2
    return 0
  fi

  # Priority 2: Base image manifest
  local base_image
  if [[ -f "$image_dir/Dockerfile" ]]; then
    base_image=$(grep -m1 '^FROM' "$image_dir/Dockerfile" | awk '{print $2}')
    if [[ -n "$base_image" ]]; then
      if detect_from_base_image_manifest "$base_image" 2>/dev/null; then
        log_debug "Using base image manifest for: $base_image"
        echo "base_image_manifest" >&2
        return 0
      fi
    fi
  fi

  # Priority 3: GitHub releases
  if detect_from_github_releases "$image_dir" 2>/dev/null; then
    log_debug "Using GitHub release binaries"
    echo "github_releases" >&2
    return 0
  fi

  # Priority 4: Download URLs
  if detect_from_download_urls "$image_dir" 2>/dev/null; then
    log_debug "Using download URL testing"
    echo "download_urls" >&2
    return 0
  fi

  # Priority 5: Conservative fallback
  log_warn "No detection method succeeded for $image_dir, using conservative default"
  echo "amd64" "arm64"
  echo "conservative_default" >&2
  return 0
}

# ==============================================================================
# Validation and Utility Functions
# ==============================================================================

# Deduplicate and normalize architecture list
# Inputs: space-separated list of architectures (may contain duplicates or variants)
# Outputs: normalized, deduplicated, sorted list (space-separated on single line)
normalize_architecture_list() {
  local temp_file
  temp_file=$(mktemp)

  for arch in "$@"; do
    # Remove any leading/trailing whitespace
    arch=$(echo "$arch" | xargs)

    local normalized
    normalized=$(normalize_architecture "$arch")

    if [[ "$normalized" != "unknown" ]]; then
      echo "$normalized" >>"$temp_file"
    fi
  done

  # Sort, deduplicate, and output (space-separated on single line)
  if [[ -f "$temp_file" ]]; then
    sort "$temp_file" | uniq | tr '\n' ' ' | sed 's/[[:space:]]*$//'
    rm -f "$temp_file"
  fi
}

# Export functions for use by other scripts
export -f normalize_architecture
export -f validate_architecture_config
export -f detect_supported_architectures
export -f normalize_architecture_list
