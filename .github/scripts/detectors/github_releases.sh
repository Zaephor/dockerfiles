#!/usr/bin/env bash
#
# GitHub Releases Version Detector
#
# Detects versions by querying GitHub Releases API for a repository.
# Supports rate limit handling and authentication via GitHub token.
#
# Usage:
#   ./github-releases.sh --config /path/to/metadata.yaml --image-name image-name
#
# Configuration (metadata.yaml):
#   version_source:
#     type: github-releases
#     repo: owner/project  # Required
#     auth_token_secret: GITHUB_TOKEN  # Optional: secret name for auth
#     prerelease_filter: false  # Optional: include pre-releases (default: false)
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

readonly DETECTOR_NAME="github-releases"
readonly GITHUB_API_BASE="https://api.github.com"

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

# Parse GitHub-specific configuration from metadata.yaml
#
# Arguments:
#   $1: Path to metadata.yaml
#
# Output:
#   repo, auth_token_secret, prerelease_filter (one per line)
#
# Returns:
#   0 on success, 2 on config error
#
parse_github_config() {
  local config_file="$1"

  if [[ ! -f "$config_file" ]]; then
    output_error "CONFIG_ERROR" "Config file not found: $config_file" "$DETECTOR_NAME"
    return 2
  fi

  # Extract repository
  local repo
  repo=$(yq eval '.version_source.repo' "$config_file" 2>/dev/null) || {
    output_error "CONFIG_ERROR" "Failed to parse version_source from $config_file" "$DETECTOR_NAME"
    return 2
  }

  if [[ -z "$repo" || "$repo" == "null" ]]; then
    output_error "CONFIG_ERROR" "Missing required field: version_source.repo" "$DETECTOR_NAME"
    return 2
  fi

  # Validate repo format (owner/project)
  if [[ ! "$repo" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$ ]]; then
    output_error "CONFIG_ERROR" "Invalid repo format: $repo (expected: owner/project)" "$DETECTOR_NAME"
    return 2
  fi

  # Extract optional auth token secret
  local auth_token_secret
  auth_token_secret=$(yq eval '.version_source.auth_token_secret' "$config_file" 2>/dev/null || echo "")
  [[ "$auth_token_secret" == "null" ]] && auth_token_secret=""

  # Extract optional prerelease filter
  local prerelease_filter
  prerelease_filter=$(yq eval '.version_source.prerelease_filter' "$config_file" 2>/dev/null || echo "false")
  [[ "$prerelease_filter" == "null" ]] && prerelease_filter="false"

  # Output parsed values
  echo "$repo"
  echo "$auth_token_secret"
  echo "$prerelease_filter"

  return 0
}

# ============================================================================
# GitHub API Interaction
# ============================================================================

# Query GitHub Releases API
#
# Arguments:
#   $1: Repository (owner/project)
#   $2: GitHub token (optional)
#
# Output:
#   JSON response from GitHub API
#
# Returns:
#   0 on success, 1 on failure
#
query_github_releases() {
  local repo="$1"
  local token="${2:-}"

  local url="${GITHUB_API_BASE}/repos/${repo}/releases"
  local headers=(-H "Accept: application/vnd.github.v3+json")

  # Add authentication if token provided
  if [[ -n "$token" ]]; then
    headers+=(-H "Authorization: token ${token}")
    if [[ "${DEBUG:-}" == "true" ]]; then
      echo "INFO: Using GitHub token for authentication" >&2
    fi
  fi

  if [[ "${DEBUG:-}" == "true" ]]; then
    echo "INFO: Querying GitHub Releases API: $url" >&2
  fi

  # Query with timeout, capture response
  local response
  response=$(timeout 30s curl -s "${headers[@]}" "$url" 2>&1) || {
    local exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
      return 1  # Timeout
    fi
    return 1  # Other error
  }

  # Check for API errors
  if echo "$response" | jq -e '.message' >/dev/null 2>&1; then
    local message
    message=$(echo "$response" | jq -r '.message' 2>/dev/null || echo "Unknown error")
    if [[ "${DEBUG:-}" == "true" ]]; then
      echo "WARN: GitHub API error: $message" >&2
    fi

    # Check for rate limit
    if [[ "$message" =~ "API rate limit exceeded" ]]; then
      return 1  # Retryable
    fi

    # Check for not found
    if [[ "$message" =~ "Not Found" ]]; then
      if [[ "${DEBUG:-}" == "true" ]]; then
        echo "ERROR: Repository not found: $repo" >&2
      fi
      return 1
    fi

    return 1
  fi

  echo "$response"
  return 0
}

# Extract latest release version from API response
#
# Arguments:
#   $1: JSON response from GitHub API
#   $2: Include pre-releases (true/false)
#
# Output:
#   Version string
#
# Returns:
#   0 on success, 1 on no releases found
#
get_latest_version_from_api() {
  local response="$1"
  local include_prerelease="${2:-false}"

  # Parse releases into array
  local releases
  releases=$(echo "$response" | jq -r '.[] | select(.draft == false | select(.prerelease == false or . == "'"$include_prerelease"'")) | .tag_name' 2>/dev/null | head -20) || {
    if [[ "${DEBUG:-}" == "true" ]]; then
      echo "ERROR: Failed to parse GitHub API response" >&2
    fi
    return 1
  }

  # Get first (latest) release
  local latest_tag
  latest_tag=$(echo "$releases" | head -1)

  if [[ -z "$latest_tag" ]]; then
    if [[ "${DEBUG:-}" == "true" ]]; then
      echo "ERROR: No releases found" >&2
    fi
    return 1
  fi

  # Normalize version (strip v prefix, etc.)
  latest_tag=$(echo "$latest_tag" | sed 's/^v//')

  echo "$latest_tag"
  return 0
}

# ============================================================================
# Detection Logic
# ============================================================================

# Perform version detection from GitHub Releases
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
  # Note: parse_github_config outputs JSON error on failure, which is captured here
  local config_output
  local exit_code
  config_output=$(parse_github_config "$config_file") || {
    exit_code=$?
    echo "$config_output"
    return $exit_code
  }

  read -r repo auth_token_secret prerelease_filter <<< "$config_output"

  if [[ "${DEBUG:-}" == "true" ]]; then
    echo "INFO: Detecting GitHub Releases version for: $repo" >&2
  fi

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

  # Query GitHub API
  local response
  response=$(query_github_releases "$repo" "$token") || {
    output_error "NETWORK_ERROR" "Failed to query GitHub Releases API for $repo" "$DETECTOR_NAME"
    return 1
  }

  # Extract latest version
  local version
  version=$(get_latest_version_from_api "$response" "$prerelease_filter") || {
    output_error "NOT_FOUND" "No releases found for $repo" "$DETECTOR_NAME"
    return 1
  }

  if [[ -z "$version" ]]; then
    output_error "PARSE_ERROR" "Failed to parse version from GitHub Releases response" "$DETECTOR_NAME"
    return 1
  fi

  # Generate source URL
  local source_url="https://github.com/${repo}/releases/tag/v${version}"

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

  if [[ "${DEBUG:-}" == "true" ]]; then
    echo "INFO: GitHub Releases detector starting for image: $image_name" >&2
  fi

  # Check cache first
  local cached_version
  if cached_version=$(get_cached_version "$image_name" 2>/dev/null); then
    if [[ "${DEBUG:-}" == "true" ]]; then
      echo "INFO: Using cached version for $image_name: $cached_version" >&2
    fi
    output_success "$cached_version" "$DETECTOR_NAME" true
    exit 0
  fi

  # Perform detection
  if [[ "${DEBUG:-}" == "true" ]]; then
    echo "INFO: Performing fresh detection for $image_name" >&2
  fi

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
    if [[ "${DEBUG:-}" == "true" ]]; then
      echo "ERROR: Detection returned empty version" >&2
    fi
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
