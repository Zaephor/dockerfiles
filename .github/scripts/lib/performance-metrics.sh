#!/bin/bash
# performance-metrics.sh - Performance metrics calculation functions
#
# Calculates and tracks performance metrics including cache hit rates and image sizes
#
# Usage:
#   source .github/scripts/lib/performance-metrics.sh
#   calculate_cache_hit_rate "$buildx_output"
#   get_image_size "$registry" "$image_tag"

set -euo pipefail

# calculate_cache_hit_rate: Calculate cache hit rate from buildx output
#
# Arguments:
#   BUILDX_OUTPUT: Full output from docker buildx build command
#
# Returns:
#   Cache hit rate as decimal (0.0 - 1.0)
#   Format: "0.75" (75% cache hit)
#
# Algorithm:
#   - Parse buildx output for "Cache HIT" and "Cache MISS" messages
#   - Calculate: hits / (hits + misses)
#
calculate_cache_hit_rate() {
  local buildx_output="$1"

  # Count cache hits and misses
  local cache_hits
  local cache_misses
  cache_hits=$(echo "$buildx_output" | grep -i "Cache HIT" | wc -l)
  cache_misses=$(echo "$buildx_output" | grep -i "Cache MISS" | wc -l)

  # Calculate hit rate
  local total=$((cache_hits + cache_misses))

  if [[ $total -eq 0 ]]; then
    # No cache info available
    echo "null"
    return 0
  fi

  # Calculate rate: hits / total
  local rate
  rate=$(awk "BEGIN {printf \"%.2f\", $cache_hits / $total}")
  echo "$rate"
}

# get_image_size: Get image size from Docker registry
#
# Arguments:
#   IMAGE_REGISTRY: Registry name (e.g., "ghcr.io")
#   IMAGE_TAG: Full image tag (e.g., "ghcr.io/user/repo/image:sha-amd64")
#
# Returns:
#   Image size in bytes
#
# Note: Requires docker/skopeo access or registry API credentials
#
get_image_size() {
  local image_tag="$1"

  # Try to get image size using docker inspect or skopeo
  # If image is available locally, use docker inspect
  if docker inspect --type image "$image_tag" &>/dev/null; then
    # Get the image config blob size and layer sizes
    local size
    size=$(docker inspect "$image_tag" --format='{{.Size}}' 2>/dev/null || echo "null")
    echo "$size"
    return 0
  fi

  # If docker inspect failed, image not available locally
  echo "null"
  return 1
}

# format_size_human: Format byte size as human-readable string
#
# Arguments:
#   SIZE_BYTES: Size in bytes
#
# Returns:
#   Formatted string (e.g., "1.2 GB", "245 MB", "15 KB")
#
format_size_human() {
  local size="$1"

  if [[ -z "$size" ]] || [[ "$size" == "null" ]]; then
    echo "unknown"
    return 0
  fi

  # Convert to human-readable format
  if [[ $size -ge 1073741824 ]]; then
    # GB
    awk "BEGIN {printf \"%.2f GB\", $size / 1073741824}"
  elif [[ $size -ge 1048576 ]]; then
    # MB
    awk "BEGIN {printf \"%.2f MB\", $size / 1048576}"
  elif [[ $size -ge 1024 ]]; then
    # KB
    awk "BEGIN {printf \"%.2f KB\", $size / 1024}"
  else
    # Bytes
    echo "$size B"
  fi
}

# calculate_size_change: Calculate size change between two builds
#
# Arguments:
#   CURRENT_SIZE: Current image size in bytes
#   PREVIOUS_SIZE: Previous image size in bytes
#
# Returns:
#   Percent change as decimal (e.g., "0.15" for 15% increase, "-0.10" for 10% decrease)
#   Format: "-0.25" or "0.50"
#
calculate_size_change() {
  local current="$1"
  local previous="$2"

  if [[ -z "$current" ]] || [[ "$current" == "null" ]] || \
     [[ -z "$previous" ]] || [[ "$previous" == "null" ]]; then
    echo "null"
    return 0
  fi

  if [[ $previous -eq 0 ]]; then
    echo "null"
    return 0
  fi

  # Calculate percent change: (current - previous) / previous
  local change
  change=$(awk "BEGIN {printf \"%.4f\", ($current - $previous) / $previous}")
  echo "$change"
}

# calculate_size_change_percent: Calculate size change as percentage
#
# Arguments:
#   CURRENT_SIZE: Current image size in bytes
#   PREVIOUS_SIZE: Previous image size in bytes
#
# Returns:
#   Percent change as integer (e.g., "15" for 15% increase, "-10" for 10% decrease)
#   Format: "-25" or "50"
#
calculate_size_change_percent() {
  local current="$1"
  local previous="$2"

  if [[ -z "$current" ]] || [[ "$current" == "null" ]] || \
     [[ -z "$previous" ]] || [[ "$previous" == "null" ]]; then
    echo "null"
    return 0
  fi

  if [[ $previous -eq 0 ]]; then
    echo "null"
    return 0
  fi

  # Calculate percent change: ((current - previous) / previous) * 100
  local change_pct
  change_pct=$(awk "BEGIN {printf \"%.0f\", (($current - $previous) / $previous) * 100}")
  echo "$change_pct"
}

# is_cache_hit_low: Check if cache hit rate is below threshold
#
# Arguments:
#   CACHE_HIT_RATE: Cache hit rate as decimal (0.0-1.0)
#   THRESHOLD: Threshold percentage (default: 0.50 for 50%)
#
# Returns:
#   0 (true) if hit rate is low
#   1 (false) if hit rate is acceptable
#
is_cache_hit_low() {
  local hit_rate="$1"
  local threshold="${2:-0.50}"

  if [[ -z "$hit_rate" ]] || [[ "$hit_rate" == "null" ]]; then
    return 1
  fi

  # Compare: if hit_rate < threshold, return 0 (true)
  awk "BEGIN {exit !($hit_rate < $threshold)}"
}

# is_image_size_increased: Check if image size increased beyond threshold
#
# Arguments:
#   SIZE_CHANGE_PERCENT: Size change as percent (e.g., "15" for 15% increase)
#   THRESHOLD: Threshold percentage (default: 20 for 20%)
#
# Returns:
#   0 (true) if size increased beyond threshold
#   1 (false) if size increase is within threshold
#
is_image_size_increased() {
  local size_change="$1"
  local threshold="${2:-20}"

  if [[ -z "$size_change" ]] || [[ "$size_change" == "null" ]]; then
    return 1
  fi

  # Compare: if size_change > threshold, return 0 (true)
  awk "BEGIN {exit !($size_change > $threshold)}"
}

export -f calculate_cache_hit_rate
export -f get_image_size
export -f format_size_human
export -f calculate_size_change
export -f calculate_size_change_percent
export -f is_cache_hit_low
export -f is_image_size_increased
