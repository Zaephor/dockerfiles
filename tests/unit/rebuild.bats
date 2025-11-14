#!/usr/bin/env bats
#
# Tests for rebuild.sh library
#

# Load the library to test
load ../../.github/scripts/lib/rebuild.sh

setup() {
  # Create temporary test directory
  export TEST_DIR="$(mktemp -d)"
  export HISTORY_FILE="${TEST_DIR}/history.jsonl"
  export IMAGE_DIR="${TEST_DIR}/test-image"

  # Create fixtures
  mkdir -p "$IMAGE_DIR"
  cp "$(dirname "$BATS_TEST_DIRNAME")"/fixtures/history-simple.jsonl "$HISTORY_FILE"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "validate_rebuild_request: accepts valid rebuild" {
  run validate_rebuild_request "test-image" "1.0.0" "$HISTORY_FILE" "$IMAGE_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"status=valid"* ]]
}

@test "validate_rebuild_request: rejects non-existent history file" {
  run validate_rebuild_request "test-image" "1.0.0" "/nonexistent/history.jsonl" "$IMAGE_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "validate_rebuild_request: rejects non-existent image directory" {
  run validate_rebuild_request "test-image" "1.0.0" "$HISTORY_FILE" "/nonexistent/dir"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "validate_rebuild_request: rejects non-existent version" {
  run validate_rebuild_request "test-image" "9.9.9" "$HISTORY_FILE" "$IMAGE_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found in history"* ]]
}

@test "generate_rebuild_history_entry: creates valid JSON structure" {
  run generate_rebuild_history_entry "1.0.0" "2025-11-13T10:30:00Z" "emergency_rollback" "abc123" "def456"
  [ "$status" -eq 0 ]
  # Should contain version and rebuild metadata
  [[ "$output" == *"\"version\": \"1.0.0\""* ]]
  [[ "$output" == *"\"rebuild_metadata\""* ]]
  [[ "$output" == *"\"reason\": \"emergency_rollback\""* ]]
}

@test "generate_rebuild_history_entry: generates without timestamp" {
  run generate_rebuild_history_entry "1.0.1" "" "emergency_rollback" "abc123" "def456"
  [ "$status" -eq 0 ]
  # Should have auto-generated timestamp
  [[ "$output" == *"\"timestamp\""* ]]
}

@test "generate_version_queue: creates queue for version range" {
  run generate_version_queue "$HISTORY_FILE" "1.0.0" "1.2.0" "--filter-status=any"
  [ "$status" -eq 0 ]
  # Should be valid JSON array
  [[ "$output" == "["* ]]
  [[ "$output" == *"]"* ]]
}

@test "generate_version_queue: filters by success status" {
  run generate_version_queue "$HISTORY_FILE" "1.0.0" "2.0.0" "--filter-status=success"
  [ "$status" -eq 0 ]
  # Should include successful versions
  [[ "$output" == *"]"* ]]
}

@test "get_queue_position: returns correct position in queue" {
  run get_queue_position "1.0.0" "1.0.0" "1.2.0" "$HISTORY_FILE"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "get_queue_position: returns position for middle version" {
  run get_queue_position "1.0.1" "1.0.0" "1.2.0" "$HISTORY_FILE"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "get_queue_position: fails for version outside range" {
  run get_queue_position "9.9.9" "1.0.0" "2.0.0" "$HISTORY_FILE"
  [ "$status" -eq 1 ]
}
