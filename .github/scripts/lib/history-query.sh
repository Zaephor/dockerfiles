#!/usr/bin/env bash
#
# History Query Library
#
# Provides functions to query build history (history.jsonl files) to extract
# version information, filter results, and support rewind scenarios.
#

set -euo pipefail

# List all versions from a history file
#
# Arguments:
#   $1: Path to history.jsonl file
#   $2: Filter type: --all (default), --original-only, --rebuilds-only
#
# Output:
#   Versions sorted chronologically (one per line), newest first
#
list_versions() {
  local history_file="$1"
  local filter="${2:---all}"

  if [[ ! -f "$history_file" ]]; then
    echo "ERROR: History file not found: $history_file" >&2
    return 1
  fi

  # Use jq to extract versions, with optional rebuild filtering
  case "$filter" in
    --original-only)
      # Only original builds (not rebuilds)
      jq -r 'select(.rebuild_metadata == null or .rebuild_metadata == {}) | .version' "$history_file" | sort -V -r
      ;;
    --rebuilds-only)
      # Only rebuild entries
      jq -r 'select(.rebuild_metadata != null and .rebuild_metadata != {}) | .version' "$history_file" | sort -V -r
      ;;
    --all|*)
      # All versions (both original and rebuilds)
      jq -r '.version' "$history_file" | sort -V -r
      ;;
  esac
}

# Get details for a specific version from history
#
# Arguments:
#   $1: Path to history.jsonl file
#   $2: Version string to search for
#
# Output:
#   JSON object with version details (full history entry)
#
get_version_details() {
  local history_file="$1"
  local version="$2"

  if [[ ! -f "$history_file" ]]; then
    echo "ERROR: History file not found: $history_file" >&2
    return 1
  fi

  # Check if version exists first
  if ! grep -F "\"version\":\"$version\"" "$history_file" > /dev/null 2>&1; then
    return 1
  fi

  # Find the most recent entry for this version (last match in file)
  grep -F "\"version\":\"$version\"" "$history_file" | tail -n1
}

# Find the original build timestamp for a version (handles rebuilds)
#
# Arguments:
#   $1: Path to history.jsonl file
#   $2: Version string
#
# Output:
#   Original build timestamp (ISO8601 format)
#
find_original_build_timestamp() {
  local history_file="$1"
  local version="$2"

  if [[ ! -f "$history_file" ]]; then
    echo "ERROR: History file not found: $history_file" >&2
    return 1
  fi

  # Find FIRST occurrence of this version (original build)
  # Iterate through file, capture first matching entry
  local found=0
  while IFS= read -r line; do
    if [[ -z "$line" ]]; then
      continue
    fi

    local current_version
    current_version=$(echo "$line" | jq -r '.version')

    if [[ "$current_version" == "$version" ]]; then
      echo "$line" | jq -r '.timestamp'
      found=1
      break
    fi
  done < "$history_file"

  if [[ $found -eq 0 ]]; then
    return 1
  fi
}

# Query versions within a range
#
# Arguments:
#   $1: Path to history.jsonl file
#   $2: Start version (inclusive)
#   $3: End version (inclusive)
#   $4: Output format: --format=simple|detailed (default: simple)
#
# Output:
#   Simple format: one version per line, sorted chronologically
#   Detailed format: JSON objects with version, timestamp, status
#
query_versions_between() {
  local history_file="$1"
  local start_version="$2"
  local end_version="$3"
  local format="${4:---format=simple}"

  if [[ ! -f "$history_file" ]]; then
    echo "ERROR: History file not found: $history_file" >&2
    return 1
  fi

  # Extract format type
  local format_type="simple"
  if [[ "$format" =~ ^--format=(.+)$ ]]; then
    format_type="${BASH_REMATCH[1]}"
  fi

  case "$format_type" in
    detailed)
      # Output detailed JSON format with version, timestamp, and status
      jq -r "
        select(
          (.version | test(\"^\" + \"$start_version\" + \"$\") or . > \"$start_version\") and
          (.version | test(\"^\" + \"$end_version\" + \"$\") or . < \"$end_version\" or . == \"$end_version\")
        ) |
        {version, timestamp, commit, architectures: (
          .architectures |
          to_entries |
          map({arch: .key, status: .value.status}) |
          from_entries
        )} | @json
      " "$history_file" | sort -V -r
      ;;
    simple|*)
      # Simple format: just version numbers, sorted by semver
      jq -r '.version' "$history_file" | sort -V | awk "
        BEGIN { start=\"$start_version\"; end=\"$end_version\"; found_start=0 }
        {
          # Compare versions using string comparison (version strings are sorted)
          if (\$0 >= start) found_start=1
          if (found_start && \$0 <= end) print \$0
          if (\$0 > end) exit
        }
      " | sort -V -r
      ;;
  esac
}

# Check if a version exists in history
#
# Arguments:
#   $1: Path to history.jsonl file
#   $2: Version string
#
# Returns:
#   0 if version exists, 1 otherwise
#
version_exists() {
  local history_file="$1"
  local version="$2"

  if [[ ! -f "$history_file" ]]; then
    return 1
  fi

  # Use -s flag to read the entire JSONL file as a stream
  if grep -F "\"version\":\"$version\"" "$history_file" > /dev/null 2>&1; then
    return 0
  fi

  return 1
}

# Get the commit SHA associated with a version
#
# Arguments:
#   $1: Path to history.jsonl file
#   $2: Version string
#
# Output:
#   Commit SHA from the original build
#
get_version_commit() {
  local history_file="$1"
  local version="$2"

  if [[ ! -f "$history_file" ]]; then
    echo "ERROR: History file not found: $history_file" >&2
    return 1
  fi

  # Get the commit from the FIRST (original) entry for this version
  local commit
  commit=$(jq -r "select(.version == \"$version\") | .commit" "$history_file" | head -n1)

  if [[ -z "$commit" || "$commit" == "null" ]]; then
    return 1
  fi

  echo "$commit"
}

# Query versions within a range with detailed output support
#
# Arguments:
#   $1: Path to history.jsonl file
#   $2: Start version (inclusive)
#   $3: End version (inclusive)
#   $4: Output format: --format=simple|detailed (default: simple)
#
# Output:
#   Formatted version list based on format parameter
#
# This function is an alias for query_versions_between for consistency
#
query_versions_in_range() {
  query_versions_between "$@"
}

# Get all versions matching a status (success/failure/partial)
#
# Arguments:
#   $1: Path to history.jsonl file
#   $2: Status filter: success|failure|partial|all (default: all)
#
# Output:
#   Versions matching the status filter, one per line
#
filter_versions_by_status() {
  local history_file="$1"
  local status_filter="${2:-all}"

  if [[ ! -f "$history_file" ]]; then
    echo "ERROR: History file not found: $history_file" >&2
    return 1
  fi

  # Determine success/failure counts for each version
  case "$status_filter" in
    success)
      # Versions where ALL architectures succeeded
      jq -r 'select(
        (
          [.architectures[] | select(.status == "success")] | length
        ) == (
          [.architectures[]] | length
        )
      ) | .version' "$history_file" | sort -V -r
      ;;
    failure)
      # Versions where ALL architectures failed
      jq -r 'select(
        (
          [.architectures[] | select(.status == "failure")] | length
        ) == (
          [.architectures[]] | length
        )
      ) | .version' "$history_file" | sort -V -r
      ;;
    partial)
      # Versions where SOME architectures failed (partial success)
      jq -r 'select(
        ([.architectures[] | select(.status == "success")] | length) > 0 and
        ([.architectures[] | select(.status == "failure")] | length) > 0
      ) | .version' "$history_file" | sort -V -r
      ;;
    all|*)
      # All versions
      jq -r '.version' "$history_file" | sort -V -r
      ;;
  esac
}

# Get detailed status of all architectures for a specific version
#
# Arguments:
#   $1: Path to history.jsonl file
#   $2: Version string
#
# Output:
#   Line per architecture: "arch: status"
#
get_version_architecture_status() {
  local history_file="$1"
  local version="$2"

  if [[ ! -f "$history_file" ]]; then
    echo "ERROR: History file not found: $history_file" >&2
    return 1
  fi

  # Extract architecture status for this version
  local entry
  entry=$(grep -F "\"version\":\"$version\"" "$history_file" | tail -n1)

  if [[ -z "$entry" ]]; then
    return 1
  fi

  # Output each architecture and its status
  echo "$entry" | jq -r '.architectures | to_entries[] | "\(.key): \(.value.status)"'
}
