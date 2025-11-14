#!/bin/bash
# retry-logic.sh - Automatic retry logic with exponential backoff for transient failures
#
# Provides functions to classify transient vs permanent failures and retry operations
# with configurable exponential backoff.
#
# Usage:
#   source .github/scripts/lib/retry-logic.sh
#   retry_with_backoff "docker push ghcr.io/myimage:latest"
#   is_transient_failure "$error_code" "$error_message"

set -euo pipefail

# is_transient_failure: Classify error as transient or permanent
#
# Arguments:
#   ERROR_CODE: Exit code or HTTP status code
#   ERROR_MESSAGE: Error message text
#
# Returns:
#   0 (true) if error is transient (should retry)
#   1 (false) if error is permanent (should not retry)
#
# Transient errors include:
#   - Network timeouts (timeout, deadline exceeded, i/o timeout)
#   - Registry unavailable (503, 502, 500 on first attempt)
#   - Rate limiting (429)
#   - Manifest not found (404 during multi-arch coordination, can be transient)
#   - Connection reset/refused (can be transient for load balancers)
#
is_transient_failure() {
  local error_code="$1"
  local error_message="$2"

  # Check for common transient error messages (case-insensitive)
  if [[ "${error_message,,}" =~ timeout|deadline\ exceeded|i/o\ timeout|connection\ reset|connection\ refused|temporarily\ unavailable ]]; then
    return 0  # Transient
  fi

  # Check HTTP status codes for transient errors
  case "$error_code" in
    429)  # Too Many Requests (rate limiting)
      return 0
      ;;
    502|503|504)  # Bad Gateway, Service Unavailable, Gateway Timeout
      return 0
      ;;
    500)  # Internal Server Error (can be transient on first attempt)
      return 0
      ;;
    404)  # Not Found - can be transient during multi-arch manifest creation
      # This is transient if it mentions "manifest" (retry after other arch completes)
      if [[ "${error_message,,}" =~ manifest|content-addressable ]]; then
        return 0
      fi
      return 1  # Permanent 404 (file not found)
      ;;
    0)  # Exit code 0 - check message for transient indicators
      # Only transient if message indicates network/timeout issues
      if [[ "${error_message,,}" =~ timeout|deadline|i/o ]]; then
        return 0
      fi
      return 1
      ;;
    *)  # Other error codes are generally permanent
      return 1
      ;;
  esac
}

# retry_with_backoff: Execute command with exponential backoff retry
#
# Arguments:
#   COMMAND: Command string to execute
#   [--max-attempts N]: Maximum retry attempts (default: 2, means 1 initial + 1 retry)
#   [--initial-delay N]: Initial backoff delay in seconds (default: 30)
#   [--max-delay N]: Maximum backoff delay in seconds (default: 300)
#
# Environment Variables:
#   RETRY_MAX_ATTEMPTS: Override --max-attempts
#   RETRY_INITIAL_DELAY: Override --initial-delay
#   RETRY_MAX_DELAY: Override --max-delay
#
# Returns:
#   0 if command succeeds
#   1 if all retry attempts exhausted
#
# Backoff strategy:
#   - Attempt 1: Immediate
#   - Attempt 2: Wait 30 seconds, retry
#   - Attempt 3: Wait 60 seconds, retry
#   - Attempt 4: Wait 120 seconds, retry (capped at max-delay)
#   - Doubles on each retry up to max-delay
#
retry_with_backoff() {
  local command="$1"
  local max_attempts="${RETRY_MAX_ATTEMPTS:-2}"
  local initial_delay="${RETRY_INITIAL_DELAY:-30}"
  local max_delay="${RETRY_MAX_DELAY:-300}"

  # Parse optional arguments
  shift || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-attempts)
        max_attempts="$2"
        shift 2
        ;;
      --initial-delay)
        initial_delay="$2"
        shift 2
        ;;
      --max-delay)
        max_delay="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done

  local attempt=1
  local delay="$initial_delay"
  local exit_code=0

  while [[ $attempt -le $max_attempts ]]; do
    echo "[RETRY] Attempt $attempt/$max_attempts: $command" >&2

    # Execute command and capture exit code
    eval "$command" && {
      echo "[RETRY] Attempt $attempt succeeded" >&2
      return 0
    } || {
      exit_code=$?
      echo "[RETRY] Attempt $attempt failed with exit code $exit_code" >&2
    }

    # Check if we should retry
    if [[ $attempt -lt $max_attempts ]]; then
      echo "[RETRY] Waiting ${delay}s before retry..." >&2
      sleep "$delay"

      # Calculate next delay (exponential backoff, capped at max_delay)
      delay=$((delay * 2))
      if [[ $delay -gt $max_delay ]]; then
        delay="$max_delay"
      fi
    fi

    attempt=$((attempt + 1))
  done

  echo "[RETRY] All $max_attempts attempts exhausted, giving up" >&2
  return 1
}

# retry_docker_push: Retry docker push with transient failure detection
#
# Arguments:
#   IMAGE_TAG: Image tag to push (e.g., ghcr.io/user/repo:digest)
#   [--max-attempts N]: Maximum attempts (default: 2)
#   [--initial-delay N]: Initial delay in seconds (default: 30)
#
# Returns:
#   0 if push succeeds
#   1 if push fails permanently
#
# This function specifically handles docker push retry logic and captures
# error output for better diagnostics.
#
retry_docker_push() {
  local image_tag="$1"
  local max_attempts="${RETRY_MAX_ATTEMPTS:-2}"
  local initial_delay="${RETRY_INITIAL_DELAY:-30}"

  shift || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-attempts)
        max_attempts="$2"
        shift 2
        ;;
      --initial-delay)
        initial_delay="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done

  local attempt=1
  local delay="$initial_delay"
  local output
  local exit_code=0

  while [[ $attempt -le $max_attempts ]]; do
    echo "[RETRY] Docker push attempt $attempt/$max_attempts: $image_tag" >&2

    # Execute push and capture output
    if output=$(docker push "$image_tag" 2>&1); then
      echo "[RETRY] Docker push succeeded on attempt $attempt" >&2
      echo "$output"
      return 0
    else
      exit_code=$?
      echo "$output" >&2
      echo "[RETRY] Docker push failed on attempt $attempt with exit code $exit_code" >&2

      # Determine if error is transient
      if ! is_transient_failure "$exit_code" "$output"; then
        echo "[RETRY] Permanent failure detected, not retrying" >&2
        return 1
      fi
    fi

    # Retry if not at max attempts
    if [[ $attempt -lt $max_attempts ]]; then
      echo "[RETRY] Waiting ${delay}s before retry..." >&2
      sleep "$delay"
      delay=$((delay * 2))
      if [[ $delay -gt 300 ]]; then
        delay=300
      fi
    fi

    attempt=$((attempt + 1))
  done

  echo "[RETRY] Docker push exhausted all $max_attempts attempts" >&2
  return 1
}

export -f is_transient_failure
export -f retry_with_backoff
export -f retry_docker_push
