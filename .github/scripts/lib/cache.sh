#!/usr/bin/env bash
#
# Cache Management Library
#
# Provides file-based caching for version detection results with 5-minute TTL.
# Cache is stored in /tmp/version-cache/ (ephemeral, cleaned between workflow runs).
#
# Reduces redundant API calls during workflow execution (e.g., matrix generation + build stages).
#

set -euo pipefail

# Allow CACHE_DIR to be overridden via environment variable (for testing)
CACHE_DIR="${CACHE_DIR:-/tmp/version-cache}"
CACHE_TTL=300  # 5 minutes in seconds

# Initialize cache directory
#
# Creates /tmp/version-cache/ if it doesn't exist
#
# Returns:
#   0 on success, 1 on failure
#
_init_cache() {
  if [[ ! -d "$CACHE_DIR" ]]; then
    mkdir -p "$CACHE_DIR" || return 1
  fi
  return 0
}

# Generate cache file path for an image
#
# Arguments:
#   $1: Image name
#
# Output:
#   Full path to cache file
#
_get_cache_file() {
  local image_name="$1"
  echo "${CACHE_DIR}/${image_name}.cache"
}

# Check if a cached version exists and is fresh (within TTL)
#
# Arguments:
#   $1: Image name
#
# Output:
#   Version string (if cache hit and fresh)
#
# Returns:
#   0 if cache hit (fresh), 1 if cache miss or expired
#
get_cached_version() {
  local image_name="$1"
  local cache_file

  _init_cache || return 1
  cache_file=$(_get_cache_file "$image_name")

  # Check if cache file exists
  if [[ ! -f "$cache_file" ]]; then
    echo "DEBUG: Cache miss for $image_name (file not found)" >&2
    return 1
  fi

  # Parse cache file (JSON format)
  # Check timestamp to see if cache is fresh
  local timestamp
  timestamp=$(jq -r '.timestamp' "$cache_file" 2>/dev/null) || {
    echo "WARN: Failed to parse cache file for $image_name" >&2
    return 1
  }

  local current_time
  current_time=$(date +%s)

  local age=$((current_time - timestamp))

  # Check if cache is fresh (within TTL) - expired if age >= TTL
  if [[ $age -ge $CACHE_TTL ]]; then
    echo "DEBUG: Cache expired for $image_name (age: ${age}s, TTL: ${CACHE_TTL}s)" >&2
    return 1
  fi

  # Extract and return version
  local version
  version=$(jq -r '.version' "$cache_file" 2>/dev/null) || {
    echo "WARN: Failed to extract version from cache for $image_name" >&2
    return 1
  }

  echo "DEBUG: Cache hit for $image_name (version: $version, age: ${age}s)" >&2
  echo "$version"
  return 0
}

# Write a version to cache
#
# Arguments:
#   $1: Image name
#   $2: Version string
#   $3: Detector name (optional, for debugging)
#   $4: Source URL (optional)
#
# Returns:
#   0 on success, 1 on failure
#
write_cache() {
  local image_name="$1"
  local version="$2"
  local detector_name="${3:-unknown}"
  local source_url="${4:-}"

  _init_cache || return 1

  local cache_file
  cache_file=$(_get_cache_file "$image_name")

  local timestamp
  timestamp=$(date +%s)

  # Create cache file with JSON content
  local cache_json
  cache_json=$(cat <<EOF
{
  "image_name": "$image_name",
  "version": "$version",
  "detector": "$detector_name",
  "source_url": "$source_url",
  "timestamp": $timestamp,
  "ttl": $CACHE_TTL
}
EOF
)

  # Ensure parent directory exists (handles image names with slashes)
  mkdir -p "$(dirname "$cache_file")" || {
    echo "WARN: Failed to create cache directory for $image_name" >&2
    return 1
  }

  # Write cache file atomically
  echo "$cache_json" > "$cache_file" || {
    echo "WARN: Failed to write cache for $image_name" >&2
    return 1
  }

  echo "DEBUG: Cached version for $image_name: $version (detector: $detector_name)" >&2
  return 0
}

# Clear cache for a specific image
#
# Arguments:
#   $1: Image name
#
# Returns:
#   0 on success, 1 on failure
#
clear_cache() {
  local image_name="$1"
  local cache_file

  cache_file=$(_get_cache_file "$image_name")

  if [[ -f "$cache_file" ]]; then
    rm -f "$cache_file" || return 1
    echo "DEBUG: Cleared cache for $image_name" >&2
  fi

  return 0
}

# Clear all cached versions
#
# Returns:
#   0 on success, 1 on failure
#
clear_all_cache() {
  if [[ -d "$CACHE_DIR" ]]; then
    rm -rf "$CACHE_DIR" || return 1
    echo "DEBUG: Cleared all cache" >&2
  fi
  return 0
}

# Get cache statistics
#
# Output:
#   JSON object with cache statistics
#
get_cache_stats() {
  local count=0
  local size=0

  _init_cache || return 1

  if [[ -d "$CACHE_DIR" ]]; then
    count=$(find "$CACHE_DIR" -name "*.cache" | wc -l)
    size=$(du -sh "$CACHE_DIR" 2>/dev/null | awk '{print $1}' || echo "0K")
  fi

  cat <<EOF
{
  "cache_dir": "$CACHE_DIR",
  "ttl_seconds": $CACHE_TTL,
  "cached_images": $count,
  "disk_usage": "$size"
}
EOF

  return 0
}

# List all cached images
#
# Output:
#   Image names (one per line)
#
list_cached() {
  if [[ -d "$CACHE_DIR" ]]; then
    find "$CACHE_DIR" -name "*.cache" -exec basename {} .cache \;
  fi
  return 0
}

# Display cache contents (for debugging)
#
# Output:
#   Cache file contents (one per line, formatted)
#
display_cache() {
  if [[ ! -d "$CACHE_DIR" ]]; then
    echo "Cache directory does not exist: $CACHE_DIR"
    return 0
  fi

  local count=0
  for cache_file in "$CACHE_DIR"/*.cache; do
    if [[ ! -f "$cache_file" ]]; then
      continue
    fi

    count=$((count + 1))
    echo "=== $(basename "$cache_file" .cache) ==="
    cat "$cache_file"
  done

  if [[ $count -eq 0 ]]; then
    echo "Cache is empty"
  fi

  return 0
}
