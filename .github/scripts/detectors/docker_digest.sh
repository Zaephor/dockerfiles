#!/usr/bin/env bash
#
# Docker Image Digest Detector
#
# Tracks the digest (SHA256) of a specific Docker image tag.
# Useful for detecting when an upstream base image changes.
#
# Usage:
#   ./docker-digest.sh --config /path/to/metadata.yaml --image-name image-name
#
# Configuration (metadata.yaml):
#   version_source:
#     type: docker_digest
#     registry: ghcr.io  # Required: registry URL (ghcr.io, docker.io, etc.)
#     image: catthehacker/ubuntu  # Required: image name (without registry)
#     tag: act-24.04  # Required: specific tag to track
#     auth_token_secret: GITHUB_TOKEN  # Optional: secret name for authentication
#
# Output:
#   Returns the image digest (sha256:...) as the "version"
#   This allows the build system to detect when the upstream image changes
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

readonly DETECTOR_NAME="docker-digest"

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
  "source_url": "${source_url}",
  "detected_at": "${timestamp}"
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

# Parse Docker digest configuration from metadata.yaml
#
# Arguments:
#   $1: Path to metadata.yaml
#
# Output:
#   registry, image, tag, auth_token_secret (one per line)
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

  # Extract required registry
  local registry
  registry=$(yq eval '.version_source.registry' "$config_file" 2>/dev/null || echo "")
  if [[ -z "$registry" || "$registry" == "null" ]]; then
    output_error "CONFIG_ERROR" "Missing required field: version_source.registry" "$DETECTOR_NAME"
    return 2
  fi

  # Extract required image
  local image
  image=$(yq eval '.version_source.image' "$config_file" 2>/dev/null || echo "")
  if [[ -z "$image" || "$image" == "null" ]]; then
    output_error "CONFIG_ERROR" "Missing required field: version_source.image" "$DETECTOR_NAME"
    return 2
  fi

  # Extract required tag
  local tag
  tag=$(yq eval '.version_source.tag' "$config_file" 2>/dev/null || echo "")
  if [[ -z "$tag" || "$tag" == "null" ]]; then
    output_error "CONFIG_ERROR" "Missing required field: version_source.tag" "$DETECTOR_NAME"
    return 2
  fi

  # Extract optional auth token secret
  local auth_token_secret
  auth_token_secret=$(yq eval '.version_source.auth_token_secret' "$config_file" 2>/dev/null || echo "")
  [[ "$auth_token_secret" == "null" ]] && auth_token_secret=""

  # Output parsed values (one per line)
  echo "$registry"
  echo "$image"
  echo "$tag"
  echo "$auth_token_secret"

  return 0
}

# ============================================================================
# Docker Registry API Queries
# ============================================================================

# Get authentication token for registry
#
# Arguments:
#   $1: Registry (e.g., ghcr.io, docker.io)
#   $2: Image name
#   $3: GitHub token (optional)
#
# Output:
#   Bearer token for registry API
#
# Returns:
#   0 on success, 1 on failure
#
get_registry_token() {
  local registry="$1"
  local image="$2"
  local github_token="$3"

  case "$registry" in
    ghcr.io)
      # GHCR requires token exchange via anonymous OAuth for public images
      local token_url="https://ghcr.io/token?scope=repository:${image}:pull"
      local token_response
      token_response=$(curl -sSL "$token_url" 2>&1) || {
        if [[ "${DEBUG:-}" == "true" ]]; then
          echo "WARN: Failed to get GHCR token" >&2
        fi
        echo ""
        return 1
      }

      local bearer_token
      bearer_token=$(echo "$token_response" | jq -r '.token // empty')
      if [[ -n "$bearer_token" ]]; then
        echo "$bearer_token"
        return 0
      fi

      echo ""
      return 1
      ;;
    docker.io|registry.hub.docker.com)
      # Docker Hub requires token exchange
      local token_url="https://auth.docker.io/token?service=registry.docker.io&scope=repository:${image}:pull"
      local token_response
      token_response=$(curl -sSL "$token_url" 2>&1) || {
        if [[ "${DEBUG:-}" == "true" ]]; then
          echo "WARN: Failed to get Docker Hub token" >&2
        fi
        echo ""
        return 1
      }

      local bearer_token
      bearer_token=$(echo "$token_response" | jq -r '.token // empty')
      if [[ -n "$bearer_token" ]]; then
        echo "$bearer_token"
        return 0
      fi

      echo ""
      return 1
      ;;
    *)
      # Generic registry
      if [[ -n "$github_token" ]]; then
        echo "$github_token"
        return 0
      fi
      echo ""
      return 0
      ;;
  esac
}

# Query Docker Registry API V2 for image manifest digest
#
# Arguments:
#   $1: Registry
#   $2: Image name
#   $3: Tag
#   $4: Auth token (optional)
#
# Output:
#   Image digest (sha256:...)
#
# Returns:
#   0 on success, 1 on failure
#
get_image_digest() {
  local registry="$1"
  local image="$2"
  local tag="$3"
  local auth_token="$4"

  # Docker Hub uses registry-1.docker.io for the registry API
  local registry_url="$registry"
  if [[ "$registry" == "docker.io" ]]; then
    registry_url="registry-1.docker.io"
  fi

  local url="https://${registry_url}/v2/${image}/manifests/${tag}"
  # Support both OCI and Docker v2 manifest formats
  local headers=(-H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json")

  # Add authentication if token provided
  if [[ -n "$auth_token" ]]; then
    headers+=(-H "Authorization: Bearer ${auth_token}")
  fi

  if [[ "${DEBUG:-}" == "true" ]]; then
    echo "INFO: Querying registry: $url" >&2
  fi

  # Query the manifest and extract Docker-Content-Digest header
  local response
  response=$(curl -sSL -D - "${headers[@]}" "$url" 2>&1) || {
    output_error "NETWORK_ERROR" "Failed to query registry: $url" "$DETECTOR_NAME"
    return 1
  }

  # Extract digest from Docker-Content-Digest header
  local digest
  digest=$(echo "$response" | grep -i "^docker-content-digest:" | cut -d' ' -f2 | tr -d '\r\n')

  if [[ -z "$digest" ]]; then
    # Fallback: try to compute digest from manifest body
    local manifest_body
    manifest_body=$(echo "$response" | sed '1,/^\r$/d')

    if [[ -n "$manifest_body" ]]; then
      digest="sha256:$(echo -n "$manifest_body" | sha256sum | cut -d' ' -f1)"
    else
      output_error "PARSE_ERROR" "Could not extract digest from registry response" "$DETECTOR_NAME"
      return 1
    fi
  fi

  echo "$digest"
  return 0
}

# ============================================================================
# Main Detection Logic
# ============================================================================

main() {
  # Parse command-line arguments
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
        output_error "USAGE_ERROR" "Unknown argument: $1" "$DETECTOR_NAME"
        return 1
        ;;
    esac
  done

  if [[ -z "$config_file" || -z "$image_name" ]]; then
    output_error "USAGE_ERROR" "Missing required arguments: --config and --image-name" "$DETECTOR_NAME"
    return 1
  fi

  # Parse configuration
  local config_output
  config_output=$(parse_docker_config "$config_file") || {
    local exit_code=$?
    echo "$config_output"
    return $exit_code
  }

  # Read multi-line output (one variable per line)
  local registry image tag auth_token_secret
  {
    read -r registry
    read -r image
    read -r tag
    read -r auth_token_secret
  } <<< "$config_output"

  if [[ "${DEBUG:-}" == "true" ]]; then
    echo "INFO: Detecting digest for: ${registry}/${image}:${tag}" >&2
  fi

  # Get authentication token if secret is specified
  local auth_token=""
  if [[ -n "$auth_token_secret" ]]; then
    # Use indirect variable expansion to get token from environment
    auth_token="${!auth_token_secret:-}"
    if [[ -z "$auth_token" ]]; then
      if [[ "${DEBUG:-}" == "true" ]]; then
        echo "WARN: Auth secret ${auth_token_secret} specified but not found in environment" >&2
        echo "WARN: Attempting anonymous access" >&2
      fi
    fi
  fi

  # Get registry token
  local registry_token
  registry_token=$(get_registry_token "$registry" "$image" "$auth_token") || {
    output_error "AUTH_ERROR" "Failed to get registry token" "$DETECTOR_NAME"
    return 1
  }

  # Check cache
  local cached_version
  if cached_version=$(get_cached_version "$image_name" 2>/dev/null); then
    if [[ "${DEBUG:-}" == "true" ]]; then
      echo "INFO: Using cached digest for ${registry}/${image}:${tag}: $cached_version" >&2
    fi
    local source_url="https://${registry}/${image}:${tag}@${cached_version}"
    output_success "$cached_version" "$DETECTOR_NAME" true "$source_url"
    return 0
  fi

  # Query registry for digest
  local digest
  digest=$(get_image_digest "$registry" "$image" "$tag" "$registry_token") || {
    return 1
  }

  if [[ -z "$digest" ]]; then
    output_error "NOT_FOUND" "No digest found for ${registry}/${image}:${tag}" "$DETECTOR_NAME"
    return 1
  fi

  # Build source URL
  local source_url="https://${registry}/${image}:${tag}@${digest}"

  # Cache the result
  write_cache "$image_name" "$digest" "$DETECTOR_NAME" "$source_url"

  # Output success
  output_success "$digest" "$DETECTOR_NAME" "false" "$source_url"
  return 0
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
