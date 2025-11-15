#!/usr/bin/env bash
# estimate-cache-hit-rate.sh - Estimate cache hit rate from build duration
#
# Usage:
#   estimate-cache-hit-rate.sh IMAGE_DIR ARCH CURRENT_DURATION
#
# Description:
#   Estimates Docker buildx cache hit rate by comparing current build
#   duration against historical average. Faster builds indicate better
#   cache utilization.
#
# Algorithm:
#   - Get average duration from last 5 successful builds
#   - Calculate improvement: (avg - current) / avg * 100
#   - Normalize to 0-100% range
#   - If no history, return null
#
# Exit Codes:
#   0 - Success (outputs percentage or "null")
#   1 - Error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries
# shellcheck source=lib/history.sh
source "$SCRIPT_DIR/lib/history.sh"

# Parse arguments
IMAGE_DIR="${1:-}"
ARCH="${2:-}"
CURRENT_DURATION="${3:-}"

if [[ -z "$IMAGE_DIR" ]] || [[ -z "$ARCH" ]] || [[ -z "$CURRENT_DURATION" ]]; then
  echo "Usage: $0 IMAGE_DIR ARCH CURRENT_DURATION" >&2
  echo "Example: $0 hello-world amd64 120" >&2
  exit 1
fi

# Convert current duration to number, handle edge cases
if [[ "$CURRENT_DURATION" == "null" ]] || [[ "$CURRENT_DURATION" == "" ]] || [[ "$CURRENT_DURATION" == "undefined" ]]; then
  echo "null"
  exit 0
fi

# Validate it's a number
if ! [[ "$CURRENT_DURATION" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  echo "null"
  exit 0
fi

HISTORY_FILE="${IMAGE_DIR}/history.jsonl"

# Check if history file exists
if [[ ! -f "$HISTORY_FILE" ]]; then
  echo "null"
  exit 0
fi

# Get average duration from last 5 successful builds
# Use calculate_average_duration function from history.sh
AVERAGE_DURATION=$(calculate_average_duration "$IMAGE_DIR" --arch "$ARCH" --last 5 2>/dev/null || echo "")

# If no average available (not enough history), return null
if [[ -z "$AVERAGE_DURATION" ]] || [[ "$AVERAGE_DURATION" == "0" ]] || [[ "$AVERAGE_DURATION" == "null" ]]; then
  echo "null"
  exit 0
fi

# Calculate cache hit rate estimate
# Formula: improvement_percent = ((avg - current) / avg) * 100
# - If current == avg: 0% improvement (baseline)
# - If current < avg: positive improvement (good cache)
# - If current > avg: negative improvement (poor cache)
#
# We map this to 0-100% cache hit rate:
# - 50% faster (current = 0.5 * avg) → ~100% cache hit
# - Same speed (current = avg) → ~50% cache hit (baseline)
# - 2x slower (current = 2 * avg) → ~0% cache hit

# Use awk for floating point math
CACHE_HIT_RATE=$(awk -v current="$CURRENT_DURATION" -v avg="$AVERAGE_DURATION" '
BEGIN {
  if (avg <= 0) {
    print "null"
    exit
  }

  # Calculate improvement ratio
  improvement = (avg - current) / avg

  # Map improvement to cache hit rate
  # improvement = 1.0 (current = 0) → 100% cache
  # improvement = 0.0 (current = avg) → 50% cache (baseline)
  # improvement = -1.0 (current = 2*avg) → 0% cache

  # Linear mapping: cache_rate = 50 + (improvement * 50)
  cache_rate = 50 + (improvement * 50)

  # Clamp to 0-100 range
  if (cache_rate > 100) cache_rate = 100
  if (cache_rate < 0) cache_rate = 0

  # Round to 1 decimal place
  printf "%.1f\n", cache_rate
}
')

# Validate output
if [[ "$CACHE_HIT_RATE" == "null" ]] || [[ -z "$CACHE_HIT_RATE" ]]; then
  echo "null"
else
  echo "$CACHE_HIT_RATE"
fi
