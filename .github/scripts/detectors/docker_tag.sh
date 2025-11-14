#!/usr/bin/env bash
#
# Docker Registry Tags Version Detector
#
# Detects versions by querying Docker Registry API V2 for available image tags.
# Supports multiple registries (Docker Hub, GHCR, Quay, private registries).
#
# Usage:
#   ./docker-tags.sh --config /path/to/metadata.yaml --image-name image-name
#
# Configuration (metadata.yaml):
#   version_source:
#     type: docker-tags
#     registry: ghcr.io  # Required: registry URL
#     image: user/repo/image-name  # Required: image name (without registry)
#     tag_filter: '^[0-9]+\.[0-9]+\.[0-9]+$'  # Optional: regex to match version tags
#     auth_token_secret: GHCR_TOKEN  # Optional: secret name for authentication
#

set -euo pipefail

# Script directory (for sourcing libraries)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Source libraries
source "${LIB_DIR}/cache.sh" || {
  echo "ERROR: Failed to source cache library" >&2
  exit 2
}

source "${LIB_DIR}/version-parser.sh" || {
  echo "ERROR: Failed to source version parser library" >&2
  exit 2
}

readonly DETECTOR_NAME="docker-tags"

# ============================================================================
# Standard JSON Output Functions
# ============================================================================

output_success() {
  local version="$1"
  local detector="$2"
  local cached="${3:-false}"
  local source_url="${4:-}"

  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  cat <<EOF
{
  "version": "${version}",
  "status": "success",
  "detector": "${detector}",
  "cached": ${cached},
  "metadata": {
    "source_url": "${source_url}",
    "detected_at": "${timestamp}"
  }
}
EOF
}

output_error() {
  local error_code="$1"
  local error_message="$2"
  local detector="${3:-unknown}"

  cat <<EOF
{
  "version": null,
  "status": "failure",
  "detector": "${detector}",
  "error": "${error_message}",
  "error_code": "${error_code}"
}
EOF
}

# ============================================================================
# Configuration Parsing
# ============================================================================

# Parse Docker registry configuration from metadata.yaml
#
# Arguments:
#   $1: Path to metadata.yaml
#
# Output:
#   registry, image, tag_filter, auth_token_secret (one per line)
#
# Returns:
#   0 on success, 2 on config error
#
parse_docker_config() {
  local config_file="$1"

  if [[ ! -f "$config_file" ]]; then
    output_error "CONFIG_ERROR" "Config file not found: $config_file" "$DETECTOR_NAME"
    return 2
  fi

  # Extract registry
  local registry
  registry=$(yq eval '.version_source.registry' "$config_file" 2>/dev/null) || {
    output_error "CONFIG_ERROR" "Failed to parse version_source from $config_file" "$DETECTOR_NAME"
    return 2
  }

  if [[ -z "$registry" || "$registry" == "null" ]]; then
    output_error "CONFIG_ERROR" "Missing required field: version_source.registry" "$DETECTOR_NAME"
    return 2
  fi

  # Extract image name
  local image
  image=$(yq eval '.version_source.image' "$config_file" 2>/dev/null) || {
    output_error "CONFIG_ERROR" "Failed to parse image from $config_file" "$DETECTOR_NAME"
    return 2
  }

  if [[ -z "$image" || "$image" == "null" ]]; then
    output_error "CONFIG_ERROR" "Missing required field: version_source.image" "$DETECTOR_NAME"
    return 2
  fi

  # Extract optional tag_filter
  local tag_filter
  tag_filter=$(yq eval '.version_source.tag_filter' "$config_file" 2>/dev/null || echo "")
  [[ "$tag_filter" == "null" ]] && tag_filter="^[0-9]"  # Default: tags starting with digit

  # Extract optional auth token secret
  local auth_token_secret
  auth_token_secret=$(yq eval '.version_source.auth_token_secret' "$config_file" 2>/dev/null || echo "")
  [[ "$auth_token_secret" == "null" ]] && auth_token_secret=""

  # Output parsed values
  echo "$registry"
  echo "$image"
  echo "$tag_filter"
  echo "$auth_token_secret"

  return 0
}

# ============================================================================
# Docker Registry API Interaction
# ============================================================================

# Query Docker Registry API V2 for image tags
#
# Arguments:
#   $1: Registry URL
#   $2: Image name
#   $3: Authentication token (optional)
#
# Output:
#   JSON response from Docker Registry API
#
# Returns:
#   0 on success, 1 on failure
#
query_docker_registry() {
  local registry="$1"
  local image="$2"
  local token="${3:-}"

  # Docker Registry API V2 endpoint
  local url="https://${registry}/v2/${image}/tags/list"

  local headers=()

  # Add authentication if token provided
  if [[ -n "$token" ]]; then
    headers+=(--header "Authorization: Bearer ${token}")
    echo "INFO: Using authentication token for Docker registry" >&2
  fi

  echo "INFO: Querying Docker Registry API: $url" >&2

  # Query with timeout
  local response
  response=$(timeout 30s curl -s "${headers[@]}" "$url" 2>&1) || {
    local exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
      return 1  # Timeout
    fi
    return 1  # Network error
  }

  # Check for API errors
  if echo "$response" | jq -e '.errors' >/dev/null 2>&1; then
    local error_code
    error_code=$(echo "$response" | jq -r '.errors[0].code' 2>/dev/null || echo "unknown")
    echo "WARN: Docker Registry error: $error_code" >&2

    if [[ "$error_code" == "UNAUTHORIZED" ]]; then
      return 1  # Auth failure
    fi

    if [[ "$error_code" == "NAME_UNKNOWN" ]]; then
      return 1  # Image not found
    fi

    return 1
  fi

  echo "$response"
  return 0
}

# Extract latest version from tag list
#
# Arguments:
#   $1: JSON response from Docker Registry API
#   $2: Tag filter regex
#
# Output:
#   Version string
#
# Returns:
#   0 on success, 1 on failure
#
get_latest_version_from_tags() {
  local response="$1"
  local tag_filter="${2:-^[0-9]}"

  # Extract tags array
  local tags
  tags=$(echo "$response" | jq -r '.tags[]?' 2>/dev/null) || {
    echo "ERROR: Failed to parse tags from Docker Registry response" >&2
    return 1
  }

  if [[ -z "$tags" ]]; then
    echo "ERROR: No tags found in registry response" >&2
    return 1
  fi

  # Filter tags using regex, exclude common non-version tags
  local filtered_tags
  filtered_tags=$(echo "$tags" | grep -E "$tag_filter" | \
    grep -v -E '^(latest|stable|edge|nightly|dev|test|staging|alpha|beta)$' | \
    head -50)

  if [[ -z "$filtered_tags" ]]; then
    echo "ERROR: No version tags found after filtering" >&2
    return 1
  fi

  # Parse all versions to find maximum
  local parsed_versions=()
  while IFS= read -r tag; do
    local parsed
    parsed=$(parse_version "$tag")
    parsed_versions+=("$parsed")
  done <<< "$filtered_tags"

  if [[ ${#parsed_versions[@]} -eq 0 ]]; then
    echo "ERROR: No valid versions found" >&2
    return 1
  fi

  # Find maximum version
  local max_version
  max_version=$(find_max_version "${parsed_versions[@]}") || {
    # Fallback: just use first tag if all are opaque
    echo "${filtered_tags[0]}"
    return 0
  }

  # Extract version value from parsed version
  local version
  version=$(get_version_value "$max_version")
  echo "$version"
  return 0
}

# ============================================================================
# Detection Logic
# ============================================================================

# Perform version detection from Docker registry
#
# Arguments:
#   $1: Path to metadata.yaml
#   $2: Image name
#
# Output:
#   Version string on success, JSON error on failure
#
# Returns:
#   0 on success, 1 on failure, 2 on config error
#
detect_version() {
  local config_file="$1"
  local image_name="$2"

  # Parse configuration
  local config_output
  config_output=$(parse_docker_config "$config_file") || return 2

  read -r registry image tag_filter auth_token_secret <<< "$config_output"

  echo "INFO: Detecting Docker tags version from: $registry/$image" >&2

  # Get authentication token if secret is specified
  local token=""
  if [[ -n "$auth_token_secret" ]]; then
    # Use indirect variable expansion to get token from environment
    token="${!auth_token_secret:-}"
    if [[ -z "$token" ]]; then
      output_error "AUTH_FAILURE" "Secret ${auth_token_secret} not found in environment" "$DETECTOR_NAME"
      return 1
    fi
  fi

  # Query Docker Registry API
  local response
  response=$(query_docker_registry "$registry" "$image" "$token") || {
    output_error "NETWORK_ERROR" "Failed to query Docker Registry API" "$DETECTOR_NAME"
    return 1
  }

  # Extract latest version
  local version
  version=$(get_latest_version_from_tags "$response" "$tag_filter") || {
    output_error "NOT_FOUND" "No version tags found in registry" "$DETECTOR_NAME"
    return 1
  }

  if [[ -z "$version" ]]; then
    output_error "PARSE_ERROR" "Failed to parse version from registry tags" "$DETECTOR_NAME"
    return 1
  fi

  # Generate source URL
  local source_url="https://${registry}/r/${image}/tags"

  echo "$version"
  echo "$source_url"
  return 0
}

# ============================================================================
# Main Entry Point
# ============================================================================

# Parse command-line arguments
parse_arguments() {
  local config_file=""
  local image_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        config_file="$2"
        shift 2
        ;;
      --image-name)
        image_name="$2"
        shift 2
        ;;
      *)
        echo "ERROR: Unknown argument: $1" >&2
        return 1
        ;;
    esac
  done

  if [[ -z "$config_file" || -z "$image_name" ]]; then
    echo "ERROR: Missing required arguments: --config and --image-name" >&2
    return 1
  fi

  echo "$config_file" "$image_name"
  return 0
}

main() {
  # Parse arguments
  local args
  args=$(parse_arguments "$@") || {
    output_error "CONFIG_ERROR" "Invalid arguments: $*" "$DETECTOR_NAME"
    exit 2
  }

  read -r config_file image_name <<< "$args"

  echo "INFO: Docker tags detector starting for image: $image_name" >&2

  # Check cache first
  local cached_version
  if cached_version=$(get_cached_version "$image_name" 2>/dev/null); then
    echo "INFO: Using cached version for $image_name: $cached_version" >&2
    output_success "$cached_version" "$DETECTOR_NAME" true
    exit 0
  fi

  # Perform detection with timeout
  echo "INFO: Performing fresh detection for $image_name" >&2

  local version
  local source_url
  local output
  local exit_code

  # Invoke detection (timeout enforced by CI/CD environment, not shell wrapper)
  # Shell functions cannot be wrapped with 'timeout' command as timeout cannot
  # execute bash functions directly. CI/CD environments enforce timeouts at job level.
  # Note: Do NOT redirect stderr here - we want INFO logs on stderr, JSON output on stdout
  output=$(detect_version "$config_file" "$image_name") || {
    exit_code=$?
    if [[ $exit_code -eq 2 ]]; then
      # Fatal configuration error
      echo "$output"
      exit 2
    else
      # Detection failed
      echo "$output"
      exit 1
    fi
  }

  # Parse output (version and source URL)
  read -r version source_url <<< "$output"

  if [[ -z "$version" ]]; then
    echo "ERROR: Detection returned empty version" >&2
    output_error "PARSE_ERROR" "Detection returned empty version" "$DETECTOR_NAME"
    exit 1
  fi

  # Cache the result
  write_cache "$image_name" "$version" "$DETECTOR_NAME" "$source_url"

  # Output success
  output_success "$version" "$DETECTOR_NAME" false "$source_url"
  exit 0
}

# Run main function
main "$@"
