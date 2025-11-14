#!/usr/bin/env bats
# performance-metrics.bats - Unit tests for performance metrics functions
#
# Tests cache hit rate calculation, image size tracking, and metrics comparisons
#

setup() {
  # Load the performance metrics library
  source .github/scripts/lib/performance-metrics.sh
}

# Test: calculate_cache_hit_rate - Perfect cache hit
@test "calculate_cache_hit_rate: perfect cache hit (100%)" {
  local buildx_output="Cache HIT for layer 1
Cache HIT for layer 2
Cache HIT for layer 3"

  run calculate_cache_hit_rate "$buildx_output"
  [ "$status" -eq 0 ]
  [ "$output" = "1.00" ]
}

# Test: calculate_cache_hit_rate - Partial cache hit
@test "calculate_cache_hit_rate: partial cache hit (66%)" {
  local buildx_output="Cache HIT for layer 1
Cache HIT for layer 2
Cache MISS for layer 3"

  run calculate_cache_hit_rate "$buildx_output"
  [ "$status" -eq 0 ]
  [ "$output" = "0.67" ]
}

# Test: calculate_cache_hit_rate - No cache hit
@test "calculate_cache_hit_rate: no cache hit (0%)" {
  local buildx_output="Cache MISS for layer 1
Cache MISS for layer 2
Cache MISS for layer 3"

  run calculate_cache_hit_rate "$buildx_output"
  [ "$status" -eq 0 ]
  [ "$output" = "0.00" ]
}

# Test: calculate_cache_hit_rate - No cache info
@test "calculate_cache_hit_rate: no cache information returns null" {
  local buildx_output="Building image...
Step 1/3: FROM ubuntu"

  run calculate_cache_hit_rate "$buildx_output"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}

# Test: calculate_cache_hit_rate - Case insensitive matching
@test "calculate_cache_hit_rate: matches cache keywords case-insensitively" {
  local buildx_output="CACHE HIT for layer 1
cache miss for layer 2
Cache HIT for layer 3"

  run calculate_cache_hit_rate "$buildx_output"
  [ "$status" -eq 0 ]
  [ "$output" = "0.67" ]
}

# Test: format_size_human - Gigabytes
@test "format_size_human: formats bytes as gigabytes" {
  run format_size_human 1073741824
  [ "$status" -eq 0 ]
  [[ "$output" =~ "1.00 GB" ]]
}

# Test: format_size_human - Megabytes
@test "format_size_human: formats bytes as megabytes" {
  run format_size_human 1048576
  [ "$status" -eq 0 ]
  [[ "$output" =~ "1.00 MB" ]]
}

# Test: format_size_human - Kilobytes
@test "format_size_human: formats bytes as kilobytes" {
  run format_size_human 1024
  [ "$status" -eq 0 ]
  [[ "$output" =~ "1.00 KB" ]]
}

# Test: format_size_human - Bytes
@test "format_size_human: formats small sizes as bytes" {
  run format_size_human 512
  [ "$status" -eq 0 ]
  [ "$output" = "512 B" ]
}

# Test: format_size_human - Null input
@test "format_size_human: handles null input" {
  run format_size_human null
  [ "$status" -eq 0 ]
  [ "$output" = "unknown" ]
}

# Test: calculate_size_change - Positive increase
@test "calculate_size_change: calculates positive increase" {
  # Current: 1100000000, Previous: 1000000000
  # Change: (1100000000 - 1000000000) / 1000000000 = 0.1 (10%)
  run calculate_size_change 1100000000 1000000000
  [ "$status" -eq 0 ]
  [ "$output" = "0.1000" ]
}

# Test: calculate_size_change - Negative decrease
@test "calculate_size_change: calculates negative decrease" {
  # Current: 900000000, Previous: 1000000000
  # Change: (900000000 - 1000000000) / 1000000000 = -0.1 (-10%)
  run calculate_size_change 900000000 1000000000
  [ "$status" -eq 0 ]
  [ "$output" = "-0.1000" ]
}

# Test: calculate_size_change - No change
@test "calculate_size_change: handles no change" {
  run calculate_size_change 1000000000 1000000000
  [ "$status" -eq 0 ]
  [ "$output" = "0.0000" ]
}

# Test: calculate_size_change - Null current size
@test "calculate_size_change: handles null current size" {
  run calculate_size_change null 1000000000
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}

# Test: calculate_size_change_percent - Positive increase
@test "calculate_size_change_percent: calculates positive percent increase" {
  # (1100000000 - 1000000000) / 1000000000 * 100 = 10
  run calculate_size_change_percent 1100000000 1000000000
  [ "$status" -eq 0 ]
  [ "$output" = "10" ]
}

# Test: calculate_size_change_percent - Negative decrease
@test "calculate_size_change_percent: calculates negative percent decrease" {
  # (900000000 - 1000000000) / 1000000000 * 100 = -10
  run calculate_size_change_percent 900000000 1000000000
  [ "$status" -eq 0 ]
  [ "$output" = "-10" ]
}

# Test: calculate_size_change_percent - Large increase
@test "calculate_size_change_percent: handles large increase (25%)" {
  # (1250000000 - 1000000000) / 1000000000 * 100 = 25
  run calculate_size_change_percent 1250000000 1000000000
  [ "$status" -eq 0 ]
  [ "$output" = "25" ]
}

# Test: is_cache_hit_low - Low cache hit below threshold
@test "is_cache_hit_low: detects low cache hit rate" {
  run is_cache_hit_low 0.40 0.50
  [ "$status" -eq 0 ]  # true
}

# Test: is_cache_hit_low - Acceptable cache hit
@test "is_cache_hit_low: accepts adequate cache hit rate" {
  run is_cache_hit_low 0.75 0.50
  [ "$status" -eq 1 ]  # false
}

# Test: is_cache_hit_low - Default threshold (50%)
@test "is_cache_hit_low: uses default 50% threshold" {
  run is_cache_hit_low 0.40
  [ "$status" -eq 0 ]  # Low
  
  run is_cache_hit_low 0.60
  [ "$status" -eq 1 ]  # Acceptable
}

# Test: is_image_size_increased - Increase exceeds threshold
@test "is_image_size_increased: detects large size increase" {
  # 25% increase > 20% threshold
  run is_image_size_increased 25 20
  [ "$status" -eq 0 ]  # true
}

# Test: is_image_size_increased - Increase within threshold
@test "is_image_size_increased: accepts size increase within threshold" {
  # 15% increase < 20% threshold
  run is_image_size_increased 15 20
  [ "$status" -eq 1 ]  # false
}

# Test: is_image_size_increased - Default threshold (20%)
@test "is_image_size_increased: uses default 20% threshold" {
  run is_image_size_increased 25
  [ "$status" -eq 0 ]  # Exceeds default
  
  run is_image_size_increased 15
  [ "$status" -eq 1 ]  # Within default
}

# Test: is_image_size_increased - Negative change (decrease)
@test "is_image_size_increased: size decrease is not flagged" {
  # -10% < 20% threshold
  run is_image_size_increased -10 20
  [ "$status" -eq 1 ]  # false
}
