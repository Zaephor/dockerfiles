#!/usr/bin/env bash
#
# Git Commit Version Detector
#
# Detects versions by querying GitHub Commits API for the latest commit on a branch.
# Returns a 7-character short SHA as the version.
#
# Usage:
#   ./git_commit.sh --config /path/to/metadata.yaml --image-name image-name
#
# Configuration (metadata.yaml):
#   version_source:
#     type: git_commit
#     repo: owner/project  # Required
#     branch: main  # Optional: branch to track (default: repo's default branch)
#     auth_token_secret: GITHUB_TOKEN  # Optional: secret name for auth
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

readonly DETECTOR_NAME="git-commit"
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

# Parse git-commit-specific configuration from metadata.yaml
#
# Arguments:
#   $1: Path to metadata.yaml
#
# Output:
#   repo, branch, auth_token_secret (one per line)
#
# Returns:
#   0 on success, 2 on config error
#
parse_git_commit_config() {
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

  # Extract optional branch (empty string means use default branch)
  local branch
  branch=$(yq eval '.version_source.branch' "$config_file" 2>/dev/null || echo "")
  [[ "$branch" == "null" ]] && branch=""

  # Extract optional auth token secret
  local auth_token_secret
  auth_token_secret=$(yq eval '.version_source.auth_token_secret' "$config_file" 2>/dev/null || echo "")
  [[ "$auth_token_secret" == "null" ]] && auth_token_secret=""

  # Output parsed values
  echo "$repo"
  echo "$branch"
  echo "$auth_token_secret"

  return 0
}

# ============================================================================
# GitHub API Interaction
# ============================================================================

# Get the default branch for a repository
#
# Arguments:
#   $1: Repository (owner/project)
#   $2: GitHub token (optional)
#
# Output:
#   Default branch name
#
# Returns:
#   0 on success, 1 on failure
#
get_default_branch() {
  local repo="$1"
  local token="${2:-}"

  local url="${GITHUB_API_BASE}/repos/${repo}"
  local headers=(-H "Accept: application/vnd.github.v3+json")

  # Add authentication if token provided
  if [[ -n "$token" ]]; then
    headers+=(-H "Authorization: token ${token}")
  fi

  if [[ "${DEBUG:-}" == "true" ]]; then
    echo "INFO: Querying GitHub repo API for default branch: $url" >&2
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
    return 1
  fi

  # Extract default branch
  local default_branch
  default_branch=$(echo "$response" | jq -r '.default_branch' 2>/dev/null)

  if [[ -z "$default_branch" || "$default_branch" == "null" ]]; then
    if [[ "${DEBUG:-}" == "true" ]]; then
      echo "ERROR: Failed to get default branch from response" >&2
    fi
    return 1
  fi

  echo "$default_branch"
  return 0
}

# Query GitHub Commits API for the latest commit on a branch
#
# Arguments:
#   $1: Repository (owner/project)
#   $2: Branch name
#   $3: GitHub token (optional)
#
# Output:
#   JSON response from GitHub API
#
# Returns:
#   0 on success, 1 on failure
#
query_github_commit() {
  local repo="$1"
  local branch="$2"
  local token="${3:-}"

  local url="${GITHUB_API_BASE}/repos/${repo}/commits/${branch}"
  local headers=(-H "Accept: application/vnd.github.v3+json")

  # Add authentication if token provided
  if [[ -n "$token" ]]; then
    headers+=(-H "Authorization: token ${token}")
    if [[ "${DEBUG:-}" == "true" ]]; then
      echo "INFO: Using GitHub token for authentication" >&2
    fi
  fi

  if [[ "${DEBUG:-}" == "true" ]]; then
    echo "INFO: Querying GitHub Commits API: $url" >&2
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
        echo "ERROR: Repository or branch not found: $repo/$branch" >&2
      fi
      return 1
    fi

    return 1
  fi

  echo "$response"
  return 0
}

# Extract short SHA from commit API response
#
# Arguments:
#   $1: JSON response from GitHub API
#
# Output:
#   7-character short SHA
#
# Returns:
#   0 on success, 1 on parse error
#
extract_short_sha() {
  local response="$1"

  # Extract full SHA
  local full_sha
  full_sha=$(echo "$response" | jq -r '.sha' 2>/dev/null) || {
    if [[ "${DEBUG:-}" == "true" ]]; then
      echo "ERROR: Failed to parse commit SHA from response" >&2
    fi
    return 1
  }

  if [[ -z "$full_sha" || "$full_sha" == "null" ]]; then
    if [[ "${DEBUG:-}" == "true" ]]; then
      echo "ERROR: No SHA found in response" >&2
    fi
    return 1
  fi

  # Return first 7 characters
  echo "${full_sha:0:7}"
  return 0
}

# Extract full SHA from commit API response (for source URL)
#
# Arguments:
#   $1: JSON response from GitHub API
#
# Output:
#   Full SHA
#
# Returns:
#   0 on success, 1 on parse error
#
extract_full_sha() {
  local response="$1"

  local full_sha
  full_sha=$(echo "$response" | jq -r '.sha' 2>/dev/null) || {
    return 1
  }

  if [[ -z "$full_sha" || "$full_sha" == "null" ]]; then
    return 1
  fi

  echo "$full_sha"
  return 0
}

# ============================================================================
# Detection Logic
# ============================================================================

# Perform version detection from GitHub Commits
#
# Arguments:
#   $1: Path to metadata.yaml
#   $2: Image name
#
# Output:
#   Version string and source URL on success, JSON error on failure
#
# Returns:
#   0 on success, 1 on failure, 2 on config error
#
detect_version() {
  local config_file="$1"
  local image_name="$2"

  # Parse configuration
  # Note: parse_git_commit_config outputs JSON error on failure, which is captured here
  local config_output
  local exit_code
  config_output=$(parse_git_commit_config "$config_file") || {
    exit_code=$?
    echo "$config_output"
    return $exit_code
  }

  local repo branch auth_token_secret
  {
    read -r repo
    read -r branch
    read -r auth_token_secret
  } <<< "$config_output"

  if [[ "${DEBUG:-}" == "true" ]]; then
    echo "INFO: Detecting git commit version for: $repo" >&2
    echo "INFO: Branch: ${branch:-<default>}" >&2
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

  # If no branch specified, get the default branch
  if [[ -z "$branch" ]]; then
    if [[ "${DEBUG:-}" == "true" ]]; then
      echo "INFO: No branch specified, querying default branch" >&2
    fi
    branch=$(get_default_branch "$repo" "$token") || {
      output_error "NETWORK_ERROR" "Failed to get default branch for $repo" "$DETECTOR_NAME"
      return 1
    }
    if [[ "${DEBUG:-}" == "true" ]]; then
      echo "INFO: Default branch is: $branch" >&2
    fi
  fi

  # Query GitHub API for latest commit
  local response
  response=$(query_github_commit "$repo" "$branch" "$token") || {
    output_error "NETWORK_ERROR" "Failed to query GitHub Commits API for $repo/$branch" "$DETECTOR_NAME"
    return 1
  }

  # Extract short SHA as version
  local version
  version=$(extract_short_sha "$response") || {
    output_error "PARSE_ERROR" "Failed to parse commit SHA from response" "$DETECTOR_NAME"
    return 1
  }

  if [[ -z "$version" ]]; then
    output_error "PARSE_ERROR" "Failed to extract version from GitHub Commits response" "$DETECTOR_NAME"
    return 1
  fi

  # Get full SHA for source URL
  local full_sha
  full_sha=$(extract_full_sha "$response") || full_sha="$version"

  # Generate source URL
  local source_url="https://github.com/${repo}/commit/${full_sha}"

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
    echo "INFO: Git commit detector starting for image: $image_name" >&2
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

  # Parse output (version and source URL on separate lines)
  local version source_url
  {
    read -r version
    read -r source_url
  } <<< "$output"

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
