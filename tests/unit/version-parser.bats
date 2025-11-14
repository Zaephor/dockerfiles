#!/usr/bin/env bats
#
# BATS Tests for Version Parser Library
#
# Tests version parsing, format detection, and comparison logic
#

# Load library
setup() {
  export TEST_DIR="$(mktemp -d)"
  source .github/scripts/lib/version-parser.sh
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ============================================================================
# Semver Parsing Tests
# ============================================================================

@test "parse_version parses simple semver (1.2.3)" {
  result=$(parse_version "1.2.3")
  [[ "$result" == "semver:1.2.3" ]]
}

@test "parse_version parses semver with v prefix (v1.2.3)" {
  result=$(parse_version "v1.2.3")
  [[ "$result" == "semver:1.2.3" ]]
}

@test "parse_version parses semver with pre-release (1.2.3-rc1)" {
  result=$(parse_version "1.2.3-rc1")
  [[ "$result" == "semver:1.2.3-rc1" ]]
}

@test "parse_version parses semver with complex pre-release (1.2.3-alpha.1)" {
  result=$(parse_version "1.2.3-alpha.1")
  [[ "$result" == "semver:1.2.3-alpha.1" ]]
}

@test "parse_version parses semver with build metadata (1.2.3+build.123)" {
  result=$(parse_version "1.2.3+build.123")
  [[ "$result" == "semver:1.2.3+build.123" ]]
}

# ============================================================================
# Calendar Version Parsing Tests
# ============================================================================

@test "parse_version parses calver YYYY.MM.DD (2024.11.13)" {
  result=$(parse_version "2024.11.13")
  [[ "$result" == "calver:2024.11.13" ]]
}

@test "parse_version parses calver YYYY.MM (2024.11)" {
  result=$(parse_version "2024.11")
  [[ "$result" == "calver:2024.11" ]]
}

@test "parse_version parses calver YY.MM.DD (24.11.13)" {
  result=$(parse_version "24.11.13")
  [[ "$result" == "calver:24.11.13" ]]
}

# ============================================================================
# Date Version Parsing Tests
# ============================================================================

@test "parse_version parses date YYYYMMDD (20241113)" {
  result=$(parse_version "20241113")
  [[ "$result" == "date:20241113" ]]
}

@test "parse_version parses date YYYY-MM-DD (2024-11-13)" {
  result=$(parse_version "2024-11-13")
  [[ "$result" == "date:2024-11-13" ]]
}

# ============================================================================
# Opaque Version Parsing Tests
# ============================================================================

@test "parse_version parses commit SHA as opaque (abc123def456)" {
  result=$(parse_version "abc123def456")
  [[ "$result" == "opaque:abc123def456" ]]
}

@test "parse_version parses rolling release as opaque (rolling)" {
  result=$(parse_version "rolling")
  [[ "$result" == "opaque:rolling" ]]
}

@test "parse_version parses edge release as opaque (edge)" {
  result=$(parse_version "edge")
  [[ "$result" == "opaque:edge" ]]
}

@test "parse_version parses latest as opaque (latest)" {
  result=$(parse_version "latest")
  [[ "$result" == "opaque:latest" ]]
}

# ============================================================================
# Format Extraction Tests
# ============================================================================

@test "get_format extracts format from parsed version (semver)" {
  result=$(get_format "semver:1.2.3")
  [[ "$result" == "semver" ]]
}

@test "get_format extracts format from parsed version (calver)" {
  result=$(get_format "calver:2024.11.13")
  [[ "$result" == "calver" ]]
}

@test "get_format extracts format from parsed version (date)" {
  result=$(get_format "date:20241113")
  [[ "$result" == "date" ]]
}

@test "get_format extracts format from parsed version (opaque)" {
  result=$(get_format "opaque:abc123")
  [[ "$result" == "opaque" ]]
}

# ============================================================================
# Version Value Extraction Tests
# ============================================================================

@test "get_version_value extracts version from parsed (semver)" {
  result=$(get_version_value "semver:1.2.3")
  [[ "$result" == "1.2.3" ]]
}

@test "get_version_value extracts version from parsed (calver)" {
  result=$(get_version_value "calver:2024.11.13")
  [[ "$result" == "2024.11.13" ]]
}

@test "get_version_value extracts version from parsed (opaque)" {
  result=$(get_version_value "opaque:rolling")
  [[ "$result" == "rolling" ]]
}

# ============================================================================
# Semantic Version Comparison Tests
# ============================================================================

@test "compare_semver: 1.2.3 == 1.2.3" {
  result=$(compare_semver "1.2.3" "1.2.3")
  [[ "$result" -eq 0 ]]
}

@test "compare_semver: 1.2.4 > 1.2.3" {
  result=$(compare_semver "1.2.4" "1.2.3")
  [[ "$result" -eq 1 ]]
}

@test "compare_semver: 1.2.3 < 1.2.4" {
  result=$(compare_semver "1.2.3" "1.2.4")
  [[ "$result" -eq -1 ]]
}

@test "compare_semver: 2.0.0 > 1.9.9" {
  result=$(compare_semver "2.0.0" "1.9.9")
  [[ "$result" -eq 1 ]]
}

@test "compare_semver: 1.10.0 > 1.9.0" {
  result=$(compare_semver "1.10.0" "1.9.0")
  [[ "$result" -eq 1 ]]
}

@test "compare_semver: 1.2.3 > 1.2.3-rc1 (release > pre-release)" {
  result=$(compare_semver "1.2.3" "1.2.3-rc1")
  [[ "$result" -eq 1 ]]
}

@test "compare_semver: 1.2.3-rc1 < 1.2.3 (pre-release < release)" {
  result=$(compare_semver "1.2.3-rc1" "1.2.3")
  [[ "$result" -eq -1 ]]
}

# ============================================================================
# Calendar Version Conversion Tests
# ============================================================================

@test "calver_to_iso_date converts YYYY.MM.DD" {
  result=$(calver_to_iso_date "2024.11.13")
  [[ "$result" == "2024-11-13" ]]
}

@test "calver_to_iso_date converts YYYY.MM to YYYY-MM-01" {
  result=$(calver_to_iso_date "2024.11")
  [[ "$result" == "2024-11-01" ]]
}

@test "calver_to_iso_date converts YY.MM.DD to 20YY-MM-DD" {
  result=$(calver_to_iso_date "24.11.13")
  [[ "$result" == "2024-11-13" ]]
}

@test "calver_to_iso_date fails on invalid format" {
  run calver_to_iso_date "invalid"
  [[ $status -eq 1 ]]
}

# ============================================================================
# Date Version Conversion Tests
# ============================================================================

@test "date_to_iso_format converts YYYYMMDD to YYYY-MM-DD" {
  result=$(date_to_iso_format "20241113")
  [[ "$result" == "2024-11-13" ]]
}

@test "date_to_iso_format keeps ISO format unchanged" {
  result=$(date_to_iso_format "2024-11-13")
  [[ "$result" == "2024-11-13" ]]
}

@test "date_to_iso_format fails on invalid format" {
  run date_to_iso_format "invalid"
  [[ $status -eq 1 ]]
}

# ============================================================================
# Full Version Comparison Tests
# ============================================================================

@test "compare_versions: semver:1.2.3 == semver:1.2.3" {
  result=$(compare_versions "semver:1.2.3" "semver:1.2.3")
  [[ "$result" -eq 0 ]]
}

@test "compare_versions: semver:1.2.4 > semver:1.2.3" {
  result=$(compare_versions "semver:1.2.4" "semver:1.2.3")
  [[ "$result" -eq 1 ]]
}

@test "compare_versions: calver:2024.11.13 > calver:2024.11.12" {
  result=$(compare_versions "calver:2024.11.13" "calver:2024.11.12")
  [[ "$result" -eq 1 ]]
}

@test "compare_versions: date:2024-11-13 > date:2024-11-12" {
  result=$(compare_versions "date:2024-11-13" "date:2024-11-12")
  [[ "$result" -eq 1 ]]
}

@test "compare_versions fails on format mismatch" {
  run compare_versions "semver:1.2.3" "calver:2024.11.13"
  [[ $status -eq 1 ]]
  [[ "$output" =~ "Cannot compare different formats" ]]
}

@test "compare_versions fails on opaque comparison" {
  run compare_versions "opaque:abc123" "opaque:def456"
  [[ $status -eq 1 ]]
  [[ "$output" =~ "cannot be compared" ]]
}

# ============================================================================
# is_newer_or_equal Tests
# ============================================================================

@test "is_newer_or_equal: 1.2.3 >= 1.2.3" {
  run is_newer_or_equal "semver:1.2.3" "semver:1.2.3"
  [[ $status -eq 0 ]]
}

@test "is_newer_or_equal: 1.2.4 >= 1.2.3" {
  run is_newer_or_equal "semver:1.2.4" "semver:1.2.3"
  [[ $status -eq 0 ]]
}

@test "is_newer_or_equal: 1.2.2 < 1.2.3" {
  run is_newer_or_equal "semver:1.2.2" "semver:1.2.3"
  [[ $status -eq 1 ]]
}

# ============================================================================
# find_max_version Tests
# ============================================================================

@test "find_max_version finds maximum semver" {
  result=$(find_max_version "semver:1.0.0" "semver:1.2.0" "semver:1.1.0")
  [[ "$result" == "semver:1.2.0" ]]
}

@test "find_max_version finds maximum calver" {
  result=$(find_max_version "calver:2024.10.01" "calver:2024.11.13" "calver:2024.11.01")
  [[ "$result" == "calver:2024.11.13" ]]
}

@test "find_max_version fails on empty list" {
  run find_max_version
  [[ $status -eq 1 ]]
  [[ "$output" =~ "No versions provided" ]]
}

# ============================================================================
# sort_versions Tests
# ============================================================================

@test "sort_versions sorts semver in ascending order" {
  result=$(sort_versions "semver:1.2.0" "semver:1.0.0" "semver:1.1.0")
  expected=$'semver:1.0.0\nsemver:1.1.0\nsemver:1.2.0'
  [[ "$result" == "$expected" ]]
}

@test "sort_versions sorts calver in ascending order" {
  result=$(sort_versions "calver:2024.11.13" "calver:2024.10.01" "calver:2024.11.01")
  expected=$'calver:2024.10.01\ncalver:2024.11.01\ncalver:2024.11.13'
  [[ "$result" == "$expected" ]]
}

@test "sort_versions fails on format mismatch" {
  run sort_versions "semver:1.2.0" "calver:2024.11.13"
  [[ $status -eq 1 ]]
  [[ "$output" =~ "Cannot compare different formats" ]]
}

# ============================================================================
# Prefix Normalization Tests
# ============================================================================

@test "normalize_prefix removes v prefix" {
  result=$(normalize_prefix "v1.2.3")
  [[ "$result" == "1.2.3" ]]
}

@test "normalize_prefix removes version- prefix" {
  result=$(normalize_prefix "version-1.2.3")
  [[ "$result" == "1.2.3" ]]
}

@test "normalize_prefix removes release- prefix" {
  result=$(normalize_prefix "release-1.2.3")
  [[ "$result" == "1.2.3" ]]
}

@test "normalize_prefix leaves unprefixed version unchanged" {
  result=$(normalize_prefix "1.2.3")
  [[ "$result" == "1.2.3" ]]
}
