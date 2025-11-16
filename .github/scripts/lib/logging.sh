#!/bin/bash
# logging.sh - Structured logging functions with timestamps and context
#
# Provides consistent, structured logging across workflows with image/architecture context
# and support for GitHub Actions annotations.
#
# Usage:
#   source .github/scripts/lib/logging.sh
#   log_structured "hello-world" "amd64" "BUILD_START" "Starting build for version 1.2.3"
#   log_error "hello-world" "arm64" "BUILD_FAILED" "Build failed with error: $error"

set -euo pipefail

# Colors for terminal output (disabled in GitHub Actions)
# Guard against multiple sourcing
if [[ -z "${RED+x}" ]]; then
  readonly RED='\033[0;31m'
  readonly YELLOW='\033[1;33m'
  readonly GREEN='\033[0;32m'
  readonly BLUE='\033[0;34m'
  readonly NC='\033[0m' # No Color
fi

# log_structured: Log message with structured format and timestamp
#
# Arguments:
#   IMAGE: Image name (e.g., "hello-world")
#   ARCH: Architecture (e.g., "amd64")
#   OPERATION: Operation name (e.g., "BUILD_START", "PUSH_RETRY", "MANIFEST_CREATE")
#   MESSAGE: Log message text
#
# Format: [TIMESTAMP] [IMAGE:ARCH] [OPERATION] MESSAGE
# Example: [2025-11-13T10:30:45Z] [hello-world:amd64] [BUILD_START] Starting build for version 1.2.3
#
# Output:
#   - STDOUT for normal logs
#   - GitHub Actions annotations for warnings/errors
#
log_structured() {
  local image="$1"
  local arch="$2"
  local operation="$3"
  local message="$4"

  # Get ISO 8601 timestamp
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Format: [TIMESTAMP] [IMAGE:ARCH] [OPERATION] MESSAGE
  local log_line="[$timestamp] [$image:$arch] [$operation] $message"

  # Check if running in GitHub Actions
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    # In GitHub Actions, output to stdout (no colors)
    echo "$log_line"
  else
    # Local terminal, add color based on operation
    case "$operation" in
      *ERROR*|*FAILED*|*FAIL)
        echo -e "${RED}$log_line${NC}"
        ;;
      *WARNING*|*WARN)
        echo -e "${YELLOW}$log_line${NC}"
        ;;
      *SUCCESS*|*COMPLETED|*COMPLETE)
        echo -e "${GREEN}$log_line${NC}"
        ;;
      *)
        echo -e "${BLUE}$log_line${NC}"
        ;;
    esac
  fi
}

# error: Log general error message without image/arch context
#
# Arguments:
#   MESSAGE: Error message
#
# Outputs:
#   - Error message to stderr
#   - GitHub Actions error annotation (if in GitHub Actions)
#
error() {
  local message="$1"

  echo "ERROR: $message" >&2

  # Add GitHub Actions annotation if available
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::$message"
  fi
}

# log_error: Log error message with GitHub Actions annotation
#
# Arguments:
#   IMAGE: Image name
#   ARCH: Architecture
#   OPERATION: Operation name
#   MESSAGE: Error message
#
# Outputs:
#   - Structured log line to stdout
#   - GitHub Actions error annotation (if in GitHub Actions)
#
log_error() {
  local image="$1"
  local arch="$2"
  local operation="$3"
  local message="$4"

  # Output structured log
  log_structured "$image" "$arch" "$operation" "ERROR: $message"

  # Add GitHub Actions annotation if available
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::[$image:$arch] $operation - $message"
  fi
}

# log_warning: Log warning message with GitHub Actions annotation
#
# Arguments:
#   IMAGE: Image name
#   ARCH: Architecture
#   OPERATION: Operation name
#   MESSAGE: Warning message
#
# Outputs:
#   - Structured log line to stdout
#   - GitHub Actions warning annotation (if in GitHub Actions)
#
log_warning() {
  local image="$1"
  local arch="$2"
  local operation="$3"
  local message="$4"

  # Output structured log
  log_structured "$image" "$arch" "$operation" "WARNING: $message"

  # Add GitHub Actions annotation if available
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::warning::[$image:$arch] $operation - $message"
  fi
}

# log_notice: Log notice message with GitHub Actions annotation
#
# Arguments:
#   IMAGE: Image name
#   ARCH: Architecture
#   OPERATION: Operation name
#   MESSAGE: Notice message
#
# Outputs:
#   - Structured log line to stdout
#   - GitHub Actions notice annotation (if in GitHub Actions)
#
log_notice() {
  local image="$1"
  local arch="$2"
  local operation="$3"
  local message="$4"

  # Output structured log
  log_structured "$image" "$arch" "$operation" "NOTICE: $message"

  # Add GitHub Actions annotation if available
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::notice::[$image:$arch] $operation - $message"
  fi
}

# log_info: Alias for log_structured (for consistency)
#
log_info() {
  log_structured "$@"
}

# log_debug: Log debug message (only if DEBUG enabled)
#
# Arguments:
#   IMAGE: Image name
#   ARCH: Architecture
#   OPERATION: Operation name
#   MESSAGE: Debug message
#
# Environment Variables:
#   DEBUG: Set to "1" or "true" to enable debug logging
#
log_debug() {
  if [[ "${DEBUG:-0}" == "1" ]] || [[ "${DEBUG:-false}" == "true" ]]; then
    log_structured "$1" "$2" "$3" "DEBUG: $4"
  fi
}

# log_metric: Log performance metric with structured format
#
# Arguments:
#   IMAGE: Image name
#   ARCH: Architecture
#   METRIC_NAME: Metric name (e.g., "CACHE_HIT_RATE", "BUILD_DURATION")
#   METRIC_VALUE: Metric value with units (e.g., "0.75" or "245s" or "1.2GB")
#
# Format: [TIMESTAMP] [IMAGE:ARCH] [METRIC] METRIC_NAME=METRIC_VALUE
#
log_metric() {
  local image="$1"
  local arch="$2"
  local metric_name="$3"
  local metric_value="$4"

  log_structured "$image" "$arch" "METRIC" "$metric_name=$metric_value"
}

# log_retry: Log retry attempt
#
# Arguments:
#   IMAGE: Image name
#   ARCH: Architecture
#   ATTEMPT: Attempt number (e.g., 1, 2, 3)
#   MAX_ATTEMPTS: Maximum attempts allowed
#   MESSAGE: Optional message explaining retry
#
log_retry() {
  local image="$1"
  local arch="$2"
  local attempt="$3"
  local max_attempts="$4"
  local message="${5:-}"

  local log_msg="RETRY attempt $attempt/$max_attempts"
  if [[ -n "$message" ]]; then
    log_msg="$log_msg: $message"
  fi

  log_structured "$image" "$arch" "RETRY" "$log_msg"
}

# log_start_section: Log section start (for grouping related logs)
#
# Arguments:
#   SECTION_NAME: Name of section (e.g., "DETERMINE_CHANGES", "BUILD_ARCH", "CREATE_MANIFEST")
#
# Outputs:
#   - GitHub Actions group start (if in GitHub Actions)
#   - Structured log line
#
log_start_section() {
  local section_name="$1"

  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::group::$section_name"
  fi

  echo "════════════════════════════════════════════════════════════"
  echo "Starting: $section_name"
  echo "════════════════════════════════════════════════════════════"
}

# log_end_section: Log section end
#
# Arguments:
#   SECTION_NAME: Name of section
#
# Outputs:
#   - GitHub Actions group end (if in GitHub Actions)
#   - Structured log line
#
log_end_section() {
  local section_name="$1"

  echo "════════════════════════════════════════════════════════════"
  echo "Completed: $section_name"
  echo "════════════════════════════════════════════════════════════"

  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::endgroup::"
  fi
}

export -f log_structured
export -f error
export -f log_error
export -f log_warning
export -f log_notice
export -f log_info
export -f log_debug
export -f log_metric
export -f log_retry
export -f log_start_section
export -f log_end_section
