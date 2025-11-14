#!/usr/bin/env bats
# logging.bats - Unit tests for structured logging functions
#
# Tests log format, timestamp generation, and GitHub Actions annotations
#

setup() {
  # Load the logging library
  source .github/scripts/lib/logging.sh

  # Unset GitHub Actions environment to test local mode
  unset GITHUB_ACTIONS
  unset DEBUG
}

teardown() {
  # Clean up environment
  unset GITHUB_ACTIONS
  unset DEBUG
}

# Test: log_structured - Output contains timestamp in ISO 8601 format
@test "log_structured: outputs ISO 8601 timestamp" {
  run log_structured "test-image" "amd64" "TEST_OP" "test message"

  # Check for ISO 8601 format: YYYY-MM-DDTHH:MM:SSZ
  [[ "$output" =~ \[.*T.*Z\] ]]
  # Check for image:arch
  [[ "$output" =~ \[test-image:amd64\] ]]
  # Check for operation
  [[ "$output" =~ \[TEST_OP\] ]]
  # Check for message
  [[ "$output" =~ "test message" ]]
}

# Test: log_structured - Contains all required fields (with optional color codes)
@test "log_structured: contains all required fields" {
  run log_structured "hello-world" "arm64" "BUILD_START" "Starting build"

  # Verify format includes all required components (ignoring color codes)
  # Strip ANSI color codes for comparison
  local clean_output
  clean_output=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')

  [[ "$clean_output" =~ ^\[[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\]\ \[hello-world:arm64\]\ \[BUILD_START\]\ Starting\ build ]]
}

# Test: log_structured - Timestamp is recent (within 2 seconds)
@test "log_structured: timestamp is current" {
  local before
  local after
  before=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  run log_structured "test" "amd64" "OP" "msg"

  after=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Strip color codes and extract timestamp
  local clean_output
  clean_output=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')

  # Extract timestamp from output [TIMESTAMP]
  local logged_time
  logged_time=$(echo "$clean_output" | grep -oP '\[\K[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z')

  # Timestamp should be between before and after
  [[ "$logged_time" == "$before" ]] || [[ "$logged_time" == "$after" ]]
}

# Test: log_error - Outputs error with annotation marker
@test "log_error: outputs error with annotation in GitHub Actions mode" {
  export GITHUB_ACTIONS=true

  run log_error "test" "amd64" "BUILD_FAILED" "Build error occurred"

  # Should contain structured log
  [[ "$output" =~ \[test:amd64\] ]]
  # Should contain error annotation
  [[ "$output" =~ "::error::" ]]
}

# Test: log_warning - Outputs warning with annotation
@test "log_warning: outputs warning with annotation in GitHub Actions mode" {
  export GITHUB_ACTIONS=true

  run log_warning "test" "amd64" "SLOW_BUILD" "Build exceeded threshold"

  # Should contain warning annotation
  [[ "$output" =~ "::warning::" ]]
}

# Test: log_notice - Outputs notice with annotation
@test "log_notice: outputs notice with annotation in GitHub Actions mode" {
  export GITHUB_ACTIONS=true

  run log_notice "test" "amd64" "INFO" "Build information"

  # Should contain notice annotation
  [[ "$output" =~ "::notice::" ]]
}

# Test: log_debug - Suppressed when DEBUG not set
@test "log_debug: suppressed when DEBUG not enabled" {
  unset DEBUG

  run log_debug "test" "amd64" "DEBUG_OP" "debug message"

  # Should produce no output
  [[ -z "$output" ]]
}

# Test: log_debug - Enabled when DEBUG=1
@test "log_debug: enabled when DEBUG=1" {
  export DEBUG=1

  run log_debug "test" "amd64" "DEBUG_OP" "debug message"

  # Should contain message
  [[ "$output" =~ "debug message" ]]
  [[ "$output" =~ "DEBUG:" ]]
}

# Test: log_debug - Enabled when DEBUG=true
@test "log_debug: enabled when DEBUG=true" {
  export DEBUG=true

  run log_debug "test" "amd64" "DEBUG_OP" "debug message"

  # Should contain message
  [[ "$output" =~ "debug message" ]]
}

# Test: log_metric - Outputs metric in standard format
@test "log_metric: outputs metric with value" {
  run log_metric "hello-world" "amd64" "CACHE_HIT_RATE" "0.75"

  # Should contain metric name and value
  [[ "$output" =~ \[hello-world:amd64\] ]]
  [[ "$output" =~ "METRIC" ]]
  [[ "$output" =~ "CACHE_HIT_RATE=0.75" ]]
}

# Test: log_metric - Handles different metric types
@test "log_metric: handles various metric formats" {
  run log_metric "test" "arm64" "BUILD_DURATION" "245s"

  [[ "$output" =~ "BUILD_DURATION=245s" ]]
}

# Test: log_retry - Outputs retry attempt number
@test "log_retry: outputs retry attempt number" {
  run log_retry "test" "amd64" 2 3 "transient failure"

  [[ "$output" =~ "attempt 2/3" ]]
  [[ "$output" =~ "transient failure" ]]
  [[ "$output" =~ "RETRY" ]]
}

# Test: log_retry - Without optional message
@test "log_retry: works without optional message" {
  run log_retry "test" "amd64" 1 2

  [[ "$output" =~ "attempt 1/2" ]]
  [[ "$output" =~ "RETRY" ]]
}

# Test: log_info - Alias for log_structured
@test "log_info: is alias for log_structured" {
  run log_info "test" "amd64" "OP" "message"

  [[ "$output" =~ \[test:amd64\] ]]
  [[ "$output" =~ \[OP\] ]]
  [[ "$output" =~ "message" ]]
}

# Test: log_start_section - Outputs section header
@test "log_start_section: outputs section header" {
  unset GITHUB_ACTIONS

  run log_start_section "BUILD_PHASE"

  # Should contain section name
  [[ "$output" =~ "BUILD_PHASE" ]]
  [[ "$output" =~ "Starting:" ]]
}

# Test: log_start_section - Adds GitHub Actions group in GitHub Actions mode
@test "log_start_section: adds GitHub Actions group marker" {
  export GITHUB_ACTIONS=true

  run log_start_section "BUILD_PHASE"

  # Should contain group marker
  [[ "$output" =~ "::group::BUILD_PHASE" ]]
}

# Test: log_end_section - Outputs section footer
@test "log_end_section: outputs section footer" {
  unset GITHUB_ACTIONS

  run log_end_section "BUILD_PHASE"

  # Should contain section name
  [[ "$output" =~ "BUILD_PHASE" ]]
  [[ "$output" =~ "Completed:" ]]
}

# Test: log_end_section - Adds GitHub Actions endgroup in GitHub Actions mode
@test "log_end_section: adds GitHub Actions endgroup marker" {
  export GITHUB_ACTIONS=true

  run log_end_section "BUILD_PHASE"

  # Should contain endgroup marker
  [[ "$output" =~ "::endgroup::" ]]
}

# Test: log_error - Error message structure
@test "log_error: includes ERROR prefix in message" {
  run log_error "test" "amd64" "BUILD_FAILED" "connection timeout"

  [[ "$output" =~ "ERROR:" ]]
  [[ "$output" =~ "connection timeout" ]]
}

# Test: log_warning - Warning message structure
@test "log_warning: includes WARNING prefix in message" {
  run log_warning "test" "amd64" "SLOW_BUILD" "build took 15 minutes"

  [[ "$output" =~ "WARNING:" ]]
  [[ "$output" =~ "build took 15 minutes" ]]
}

# Test: log_notice - Notice message structure
@test "log_notice: includes NOTICE prefix in message" {
  run log_notice "test" "amd64" "INFO" "skipping build"

  [[ "$output" =~ "NOTICE:" ]]
  [[ "$output" =~ "skipping build" ]]
}
