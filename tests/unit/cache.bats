#!/usr/bin/env bats
#
# BATS Tests for Cache Management Library
#
# Tests file-based version caching with TTL
#

# Load library
setup() {
  export TEST_DIR="$(mktemp -d)"
  export CACHE_DIR="${TEST_DIR}/version-cache"
  # Override CACHE_DIR before sourcing to use temp location
  source .github/scripts/lib/cache.sh
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ============================================================================
# Cache Directory Initialization Tests
# ============================================================================

@test "_init_cache creates cache directory" {
  [[ ! -d "$CACHE_DIR" ]]
  run _init_cache
  [[ $status -eq 0 ]]
  [[ -d "$CACHE_DIR" ]]
}

@test "_init_cache succeeds if cache directory already exists" {
  mkdir -p "$CACHE_DIR"
  run _init_cache
  [[ $status -eq 0 ]]
}

# ============================================================================
# Cache File Path Generation Tests
# ============================================================================

@test "_get_cache_file returns correct path" {
  result=$(_get_cache_file "test-image")
  [[ "$result" == "${CACHE_DIR}/test-image.cache" ]]
}

@test "_get_cache_file works with image names containing hyphens" {
  result=$(_get_cache_file "test-image-name")
  [[ "$result" == "${CACHE_DIR}/test-image-name.cache" ]]
}

# ============================================================================
# Cache Write Tests
# ============================================================================

@test "write_cache creates cache file with JSON content" {
  mkdir -p "$CACHE_DIR"
  run write_cache "test-image" "1.2.3" "test-detector" "https://example.com"
  [[ $status -eq 0 ]]
  [[ -f "${CACHE_DIR}/test-image.cache" ]]
}

@test "write_cache stores correct version in cache" {
  mkdir -p "$CACHE_DIR"
  write_cache "test-image" "1.2.3" "test-detector" "https://example.com"
  cached_version=$(jq -r '.version' "${CACHE_DIR}/test-image.cache")
  [[ "$cached_version" == "1.2.3" ]]
}

@test "write_cache stores correct detector name in cache" {
  mkdir -p "$CACHE_DIR"
  write_cache "test-image" "1.2.3" "my-detector" "https://example.com"
  cached_detector=$(jq -r '.detector' "${CACHE_DIR}/test-image.cache")
  [[ "$cached_detector" == "my-detector" ]]
}

@test "write_cache stores correct image name in cache" {
  mkdir -p "$CACHE_DIR"
  write_cache "my-image" "1.2.3" "test-detector" "https://example.com"
  cached_image=$(jq -r '.image_name' "${CACHE_DIR}/my-image.cache")
  [[ "$cached_image" == "my-image" ]]
}

@test "write_cache stores timestamp in cache" {
  mkdir -p "$CACHE_DIR"
  before=$(date +%s)
  write_cache "test-image" "1.2.3" "test-detector" "https://example.com"
  after=$(date +%s)
  cached_ts=$(jq -r '.timestamp' "${CACHE_DIR}/test-image.cache")
  [[ $cached_ts -ge $before && $cached_ts -le $after ]]
}

@test "write_cache stores TTL value in cache" {
  mkdir -p "$CACHE_DIR"
  write_cache "test-image" "1.2.3" "test-detector" "https://example.com"
  cached_ttl=$(jq -r '.ttl' "${CACHE_DIR}/test-image.cache")
  [[ "$cached_ttl" == "300" ]]
}

# ============================================================================
# Cache Read Tests
# ============================================================================

@test "get_cached_version returns version on cache hit" {
  mkdir -p "$CACHE_DIR"
  write_cache "test-image" "1.2.3" "test-detector" "https://example.com"
  result=$(get_cached_version "test-image" 2>/dev/null)
  [[ "$result" == "1.2.3" ]]
}

@test "get_cached_version returns 1 on cache miss (file not found)" {
  mkdir -p "$CACHE_DIR"
  run get_cached_version "nonexistent-image" 2>/dev/null
  [[ $status -eq 1 ]]
}

@test "get_cached_version returns 1 on expired cache" {
  mkdir -p "$CACHE_DIR"

  # Create a cache entry with past timestamp (> 300 seconds old)
  past_timestamp=$(($(date +%s) - 400))
  cache_file="${CACHE_DIR}/test-image.cache"

  cat > "$cache_file" <<EOF
{
  "image_name": "test-image",
  "version": "1.2.3",
  "detector": "test-detector",
  "timestamp": $past_timestamp,
  "ttl": 300
}
EOF

  run get_cached_version "test-image" 2>/dev/null
  [[ $status -eq 1 ]]
}

@test "get_cached_version returns 0 on fresh cache (within TTL)" {
  mkdir -p "$CACHE_DIR"
  current_timestamp=$(date +%s)
  cache_file="${CACHE_DIR}/test-image.cache"

  cat > "$cache_file" <<EOF
{
  "image_name": "test-image",
  "version": "1.2.3",
  "detector": "test-detector",
  "timestamp": $current_timestamp,
  "ttl": 300
}
EOF

  run get_cached_version "test-image" 2>/dev/null
  [[ $status -eq 0 ]]
}

@test "get_cached_version handles malformed JSON gracefully" {
  mkdir -p "$CACHE_DIR"
  echo "not valid json" > "${CACHE_DIR}/test-image.cache"
  run get_cached_version "test-image" 2>/dev/null
  [[ $status -eq 1 ]]
}

# ============================================================================
# Cache Clear Tests
# ============================================================================

@test "clear_cache removes specific cache file" {
  mkdir -p "$CACHE_DIR"
  write_cache "test-image" "1.2.3" "test-detector" "https://example.com"
  [[ -f "${CACHE_DIR}/test-image.cache" ]]
  run clear_cache "test-image"
  [[ $status -eq 0 ]]
  [[ ! -f "${CACHE_DIR}/test-image.cache" ]]
}

@test "clear_cache succeeds if file doesn't exist" {
  mkdir -p "$CACHE_DIR"
  run clear_cache "nonexistent-image"
  [[ $status -eq 0 ]]
}

@test "clear_all_cache removes entire cache directory" {
  mkdir -p "$CACHE_DIR"
  write_cache "test-image-1" "1.2.3" "test-detector" "https://example.com"
  write_cache "test-image-2" "2.0.0" "test-detector" "https://example.com"
  [[ -d "$CACHE_DIR" ]]
  run clear_all_cache
  [[ $status -eq 0 ]]
  [[ ! -d "$CACHE_DIR" ]]
}

# ============================================================================
# Cache Statistics Tests
# ============================================================================

@test "get_cache_stats returns JSON with correct fields" {
  mkdir -p "$CACHE_DIR"
  write_cache "test-image" "1.2.3" "test-detector" "https://example.com"
  result=$(get_cache_stats)

  # Verify JSON is valid
  echo "$result" | jq . >/dev/null

  # Verify required fields
  echo "$result" | jq -e '.cache_dir' >/dev/null
  echo "$result" | jq -e '.ttl_seconds' >/dev/null
  echo "$result" | jq -e '.cached_images' >/dev/null
  echo "$result" | jq -e '.disk_usage' >/dev/null
}

@test "get_cache_stats shows correct count of cached images" {
  mkdir -p "$CACHE_DIR"
  write_cache "image-1" "1.0.0" "test-detector" ""
  write_cache "image-2" "2.0.0" "test-detector" ""
  result=$(get_cache_stats)
  count=$(echo "$result" | jq -r '.cached_images')
  [[ "$count" -eq 2 ]]
}

# ============================================================================
# Cache Listing Tests
# ============================================================================

@test "list_cached shows all cached image names" {
  mkdir -p "$CACHE_DIR"
  write_cache "image-1" "1.0.0" "test-detector" ""
  write_cache "image-2" "2.0.0" "test-detector" ""
  result=$(list_cached | sort)
  expected=$'image-1\nimage-2'
  [[ "$result" == "$expected" ]]
}

@test "list_cached returns empty on no cached images" {
  mkdir -p "$CACHE_DIR"
  result=$(list_cached)
  [[ -z "$result" ]]
}

# ============================================================================
# Cache Display Tests
# ============================================================================

@test "display_cache shows cache contents" {
  mkdir -p "$CACHE_DIR"
  write_cache "test-image" "1.2.3" "test-detector" ""
  run display_cache 2>&1
  [[ "$output" =~ "test-image" ]]
  [[ "$output" =~ "1.2.3" ]]
}

@test "display_cache shows message on empty cache" {
  mkdir -p "$CACHE_DIR"
  run display_cache 2>&1
  [[ "$output" =~ "Cache is empty" ]]
}

# ============================================================================
# Cache Expiration Boundary Tests
# ============================================================================

@test "get_cached_version returns hit for cache at TTL boundary (300s)" {
  mkdir -p "$CACHE_DIR"
  # Create cache exactly 300 seconds old (at TTL boundary)
  past_timestamp=$(($(date +%s) - 300))
  cache_file="${CACHE_DIR}/test-image.cache"

  cat > "$cache_file" <<EOF
{
  "image_name": "test-image",
  "version": "1.2.3",
  "detector": "test-detector",
  "timestamp": $past_timestamp,
  "ttl": 300
}
EOF

  # Should be expired (> 300 seconds)
  run get_cached_version "test-image" 2>/dev/null
  [[ $status -eq 1 ]]
}

@test "get_cached_version returns hit for cache just under TTL (299s)" {
  mkdir -p "$CACHE_DIR"
  # Create cache 295 seconds old (still fresh, with buffer for execution time)
  past_timestamp=$(($(date +%s) - 295))
  cache_file="${CACHE_DIR}/test-image.cache"

  cat > "$cache_file" <<EOF
{
  "image_name": "test-image",
  "version": "1.2.3",
  "detector": "test-detector",
  "timestamp": $past_timestamp,
  "ttl": 300
}
EOF

  run get_cached_version "test-image" 2>/dev/null
  [[ $status -eq 0 ]]
  [[ "$output" =~ "1.2.3" ]]
}

# ============================================================================
# Multiple Cache Entries Tests
# ============================================================================

@test "Multiple cache entries work independently" {
  mkdir -p "$CACHE_DIR"
  write_cache "image-1" "1.0.0" "detector-1" ""
  write_cache "image-2" "2.0.0" "detector-2" ""

  v1=$(get_cached_version "image-1" 2>/dev/null)
  v2=$(get_cached_version "image-2" 2>/dev/null)

  [[ "$v1" == "1.0.0" ]]
  [[ "$v2" == "2.0.0" ]]
}

@test "Clearing one cache entry preserves others" {
  mkdir -p "$CACHE_DIR"
  write_cache "image-1" "1.0.0" "detector-1" ""
  write_cache "image-2" "2.0.0" "detector-2" ""

  clear_cache "image-1"

  run get_cached_version "image-1" 2>/dev/null
  [[ $status -eq 1 ]]

  v2=$(get_cached_version "image-2" 2>/dev/null)
  [[ "$v2" == "2.0.0" ]]
}
