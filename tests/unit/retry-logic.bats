#!/usr/bin/env bats
# retry-logic.bats - Unit tests for retry logic functions
#
# Tests error classification, backoff calculation, and retry behavior
#

setup() {
  # Load the retry logic library
  source .github/scripts/lib/retry-logic.sh

  # Create temp directory for test artifacts
  export TEST_DIR="$(mktemp -d)"

  # Track retry attempt count
  export RETRY_ATTEMPT_COUNT=0
}

teardown() {
  # Clean up test directory
  rm -rf "$TEST_DIR"
  unset RETRY_ATTEMPT_COUNT
}

# Test: is_transient_failure - Timeout errors are transient
@test "is_transient_failure: timeout error is transient" {
  run is_transient_failure 1 "timeout: deadline exceeded"
  [ "$status" -eq 0 ]  # Should return true (0)
}

# Test: is_transient_failure - I/O timeout is transient
@test "is_transient_failure: i/o timeout is transient" {
  run is_transient_failure 1 "i/o timeout"
  [ "$status" -eq 0 ]
}

# Test: is_transient_failure - Connection reset is transient
@test "is_transient_failure: connection reset is transient" {
  run is_transient_failure 1 "connection reset by peer"
  [ "$status" -eq 0 ]
}

# Test: is_transient_failure - 503 Service Unavailable is transient
@test "is_transient_failure: HTTP 503 is transient" {
  run is_transient_failure 503 "Service Unavailable"
  [ "$status" -eq 0 ]
}

# Test: is_transient_failure - 502 Bad Gateway is transient
@test "is_transient_failure: HTTP 502 is transient" {
  run is_transient_failure 502 "Bad Gateway"
  [ "$status" -eq 0 ]
}

# Test: is_transient_failure - 504 Gateway Timeout is transient
@test "is_transient_failure: HTTP 504 is transient" {
  run is_transient_failure 504 "Gateway Timeout"
  [ "$status" -eq 0 ]
}

# Test: is_transient_failure - 429 Too Many Requests is transient
@test "is_transient_failure: HTTP 429 rate limit is transient" {
  run is_transient_failure 429 "too many requests"
  [ "$status" -eq 0 ]
}

# Test: is_transient_failure - 404 manifest error is transient
@test "is_transient_failure: HTTP 404 manifest not found is transient" {
  run is_transient_failure 404 "manifest not found"
  [ "$status" -eq 0 ]
}

# Test: is_transient_failure - Regular 404 is permanent
@test "is_transient_failure: HTTP 404 file not found is permanent" {
  run is_transient_failure 404 "file not found"
  [ "$status" -eq 1 ]  # Should return false (1)
}

# Test: is_transient_failure - Dockerfile error is permanent
@test "is_transient_failure: dockerfile parse error is permanent" {
  run is_transient_failure 1 "dockerfile: parse error"
  [ "$status" -eq 1 ]
}

# Test: is_transient_failure - Authentication error is permanent
@test "is_transient_failure: authentication error is permanent" {
  run is_transient_failure 401 "unauthorized: authentication required"
  [ "$status" -eq 1 ]
}

# Test: is_transient_failure - Permission error is permanent
@test "is_transient_failure: permission denied is permanent" {
  run is_transient_failure 403 "permission denied"
  [ "$status" -eq 1 ]
}

# Test: retry_with_backoff - Success on first attempt
@test "retry_with_backoff: succeeds on first attempt" {
  # Create a command that succeeds immediately
  local result_file="$TEST_DIR/result.txt"

  run retry_with_backoff "echo 'success' > $result_file"
  [ "$status" -eq 0 ]
  [ -f "$result_file" ]
  [ "$(cat $result_file)" = "success" ]
}

# Test: retry_with_backoff - Fails immediately on permanent error
@test "retry_with_backoff: fails immediately on permanent failure" {
  # Create a command that always fails
  run retry_with_backoff "false" --max-attempts 2 --initial-delay 1
  [ "$status" -eq 1 ]
}

# Test: retry_with_backoff - Retries after transient failure
@test "retry_with_backoff: retries after first failure" {
  # Create a command that fails first, then succeeds
  local attempt_file="$TEST_DIR/attempts.txt"

  # Command: increment counter, fail if count < 2, succeed otherwise
  local cmd="echo \$(( \$(cat $attempt_file 2>/dev/null || echo 0) + 1 )) > $attempt_file && [ \$(cat $attempt_file) -gt 1 ]"

  run retry_with_backoff "$cmd" --max-attempts 3 --initial-delay 1
  [ "$status" -eq 0 ]
  # Should have 2 attempts in file (1 failed, 1 succeeded)
  [ "$(cat $attempt_file)" = "2" ]
}

# Test: is_transient_failure - Mixed case timeout matching
@test "is_transient_failure: timeout matching handles mixed case" {
  run is_transient_failure 1 "Timeout: deadline exceeded"
  [ "$status" -eq 0 ]
}

# Test: is_transient_failure - Mixed case connection matching
@test "is_transient_failure: connection matching handles mixed case" {
  run is_transient_failure 1 "Connection Reset by peer"
  [ "$status" -eq 0 ]
}

# Test: retry_with_backoff - Max delay caps exponential backoff
@test "retry_with_backoff: max delay caps backoff growth" {
  local start_time
  local end_time
  local elapsed

  start_time=$(date +%s)

  # Command that always fails - should retry twice with capped delays
  # Initial delay: 5, second delay: min(10, 15 max) = 10
  # Total wait: 5 + 10 = 15 seconds (plus execution time)
  run retry_with_backoff "false" --max-attempts 3 --initial-delay 5 --max-delay 15

  end_time=$(date +%s)
  elapsed=$((end_time - start_time))

  [ "$status" -eq 1 ]  # Should still fail after retries exhausted
  # Should wait at least 15 seconds (5 + 10 with capped max-delay)
  [ $elapsed -ge 14 ]  # Allow 1 second margin for execution
}

# Test: is_transient_failure - Exit code 0 with timeout message
@test "is_transient_failure: exit code 0 with timeout message is transient" {
  run is_transient_failure 0 "timeout waiting for response"
  [ "$status" -eq 0 ]
}

# Test: is_transient_failure - Exit code 0 with permanent error message
@test "is_transient_failure: exit code 0 with permanent error is permanent" {
  run is_transient_failure 0 "unknown command"
  [ "$status" -eq 1 ]
}

# Test: retry_with_backoff - Environment variables override defaults
@test "retry_with_backoff: environment variables override defaults" {
  export RETRY_MAX_ATTEMPTS=1
  export RETRY_INITIAL_DELAY=1

  local attempt_file="$TEST_DIR/attempts.txt"

  # Try to run command that always fails
  # With max-attempts=1, should not retry
  local cmd="echo 1 >> $attempt_file && false"

  run retry_with_backoff "$cmd"
  [ "$status" -eq 1 ]

  # Should only have 1 attempt (no retries)
  [ "$(wc -l < $attempt_file)" -eq 1 ]

  unset RETRY_MAX_ATTEMPTS
  unset RETRY_INITIAL_DELAY
}
