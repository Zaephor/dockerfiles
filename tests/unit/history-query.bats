#!/usr/bin/env bats
#
# Tests for history-query.sh library
#

# Load the library to test
load ../../.github/scripts/lib/history-query.sh

setup() {
  # Create temporary test directory
  export TEST_DIR="$(mktemp -d)"
  export HISTORY_SIMPLE="${TEST_DIR}/history-simple.jsonl"
  export HISTORY_FAILURES="${TEST_DIR}/history-failures.jsonl"

  # Copy fixtures to test directory
  cp "$(dirname "$BATS_TEST_DIRNAME")"/fixtures/history-simple.jsonl "$HISTORY_SIMPLE"
  cp "$(dirname "$BATS_TEST_DIRNAME")"/fixtures/history-failures.jsonl "$HISTORY_FAILURES"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "list_versions: returns all versions from history" {
  run list_versions "$HISTORY_SIMPLE"
  [ "$status" -eq 0 ]
  # Check that output contains expected versions
  [[ "$output" == *"2.0.1"* ]]
  [[ "$output" == *"1.0.0"* ]]
}

@test "list_versions: returns versions in descending order" {
  run list_versions "$HISTORY_SIMPLE"
  [ "$status" -eq 0 ]
  # First version should be 2.0.1 (latest)
  local first_line=$(echo "$output" | head -n1)
  [ "$first_line" = "2.0.1" ]
}

@test "list_versions: returns all versions with --all filter" {
  run list_versions "$HISTORY_SIMPLE" "--all"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2.0.1"* ]]
  [[ "$output" == *"1.0.0"* ]]
}

@test "list_versions: handles missing file" {
  run list_versions "/nonexistent/path/history.jsonl"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "get_version_details: returns JSON for existing version" {
  run get_version_details "$HISTORY_SIMPLE" "1.0.0"
  [ "$status" -eq 0 ]
  # Output should contain version
  [[ "$output" == *"1.0.0"* ]]
}

@test "get_version_details: fails for non-existent version" {
  run get_version_details "$HISTORY_SIMPLE" "9.9.9"
  [ "$status" -eq 1 ]
}

@test "get_version_details: handles missing history file" {
  run get_version_details "/nonexistent/path/history.jsonl" "1.0.0"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "find_original_build_timestamp: returns timestamp for version 1.0.0" {
  run find_original_build_timestamp "$HISTORY_SIMPLE" "1.0.0"
  [ "$status" -eq 0 ]
  # Should be ISO8601 format
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "find_original_build_timestamp: returns timestamp for version 2.0.1" {
  run find_original_build_timestamp "$HISTORY_SIMPLE" "2.0.1"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "find_original_build_timestamp: fails for non-existent version" {
  run find_original_build_timestamp "$HISTORY_SIMPLE" "9.9.9"
  [ "$status" -eq 1 ]
}

@test "query_versions_between: returns versions in range (simple format)" {
  run query_versions_between "$HISTORY_SIMPLE" "1.0.0" "1.2.0" "--format=simple"
  [ "$status" -eq 0 ]
  # Should include versions in range
  [[ "$output" == *"1.0.0"* ]]
  [[ "$output" == *"1.0.1"* ]]
  [[ "$output" == *"1.0.2"* ]]
}

@test "query_versions_between: excludes versions outside range" {
  run query_versions_between "$HISTORY_SIMPLE" "1.0.0" "1.0.2" "--format=simple"
  [ "$status" -eq 0 ]
  # Should not include 1.1.0
  [[ "$output" != *"1.1.0"* ]]
}

@test "query_versions_between: handles missing file" {
  run query_versions_between "/nonexistent/path/history.jsonl" "1.0.0" "2.0.0" "--format=simple"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "version_exists: returns 0 for existing version" {
  run version_exists "$HISTORY_SIMPLE" "1.0.0"
  [ "$status" -eq 0 ]
}

@test "version_exists: returns 1 for non-existent version" {
  run version_exists "$HISTORY_SIMPLE" "9.9.9"
  [ "$status" -eq 1 ]
}

@test "version_exists: handles missing file" {
  run version_exists "/nonexistent/path/history.jsonl" "1.0.0"
  [ "$status" -eq 1 ]
}

@test "get_version_commit: returns commit SHA for version" {
  run get_version_commit "$HISTORY_SIMPLE" "1.0.0"
  [ "$status" -eq 0 ]
  [ "$output" = "abc123def456" ]
}

@test "get_version_commit: handles non-existent version" {
  run get_version_commit "$HISTORY_SIMPLE" "9.9.9"
  [ "$status" -eq 1 ]
}

@test "get_version_commit: handles missing file" {
  run get_version_commit "/nonexistent/path/history.jsonl" "1.0.0"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "filter_versions_by_status: gets all successful versions" {
  run filter_versions_by_status "$HISTORY_FAILURES" "success"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1.0.0"* ]]
  [[ "$output" == *"1.0.2"* ]]
}

@test "filter_versions_by_status: gets all failed versions" {
  run filter_versions_by_status "$HISTORY_FAILURES" "failure"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1.0.1"* ]]
  [[ "$output" == *"1.2.0"* ]]
}

@test "filter_versions_by_status: gets partial success versions" {
  run filter_versions_by_status "$HISTORY_FAILURES" "partial"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1.1.0"* ]]
}

@test "get_version_architecture_status: returns architecture statuses" {
  run get_version_architecture_status "$HISTORY_SIMPLE" "1.0.0"
  [ "$status" -eq 0 ]
  [[ "$output" == *"amd64"* ]]
  [[ "$output" == *"arm64"* ]]
  [[ "$output" == *"success"* ]]
}

@test "query_versions_in_range: alias for query_versions_between" {
  run query_versions_in_range "$HISTORY_SIMPLE" "1.0.0" "1.2.0" "--format=simple"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1.0.0"* ]]
}
