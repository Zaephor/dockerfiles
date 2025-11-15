#!/bin/bash
# history.sh - Build history management functions
#
# Manages append-only build history (JSONL format) for images.
# Provides functions to append build records with performance metrics.
#
# Usage:
#   source .github/scripts/lib/history.sh
#   append_build_record IMAGE_DIR VERSION COMMIT BRANCH STATUS \
#     [--start START_TIMESTAMP] [--end END_TIMESTAMP] [--duration DURATION] [--digest DIGEST] [--arch ARCH]

set -euo pipefail

# append_build_record: Add a new build record to image history
#
# Arguments:
#   IMAGE_DIR: Image directory name (e.g., "hello-world")
#   VERSION: Version string (e.g., "1.2.3")
#   COMMIT: Commit SHA (short or long form)
#   BRANCH: Branch name
#   ARCH: Architecture (amd64, arm64)
#   STATUS: Build status (success, failure)
#   [--start START_TS]: Unix timestamp when build started (optional)
#   [--end END_TS]: Unix timestamp when build ended (optional)
#   [--duration DURATION]: Build duration in seconds (optional)
#   [--digest DIGEST]: Image digest (optional)
#   [--retry-count RETRIES]: Number of retries attempted (optional, Sprint 13)
#   [--cache-hit-rate RATE]: Cache hit rate as decimal (0.0-1.0) (optional, Sprint 13)
#   [--image-size SIZE]: Image size in bytes (optional, Sprint 13)
#   [--image-size-change CHANGE]: Image size change in bytes (optional, Sprint 13)
#
# History File Location: {IMAGE_DIR}/history.jsonl
#
# Example:
#   append_build_record hello-world 1.2.3 abc123 main amd64 success \
#     --start 1699790400 --end 1699790645 --duration 245 --digest sha256:deadbeef \
#     --retry-count 1 --cache-hit-rate 0.75 --image-size 1073741824
#
# Schema (JSONL format, one record per line):
# {
#   "version": "1.2.3",
#   "timestamp": "2025-11-12T10:30:00Z",
#   "commit": "abc123",
#   "branch": "main",
#   "manual_trigger": false,
#   "trigger_overrides": null,
#   "architectures": {
#     "amd64": {
#       "status": "success",
#       "digest": "sha256:deadbeef...",
#       "duration_seconds": 245,
#       "start_timestamp": 1699790400,
#       "end_timestamp": 1699790645,
#       "retry_count": 0,
#       "cache_hit_rate": 0.75,
#       "image_size": 1073741824,
#       "image_size_change": 0
#     }
#   }
# }
#
append_build_record() {
  local image_dir="$1"
  local version="$2"
  local commit="$3"
  local branch="$4"
  local arch="$5"
  local status="$6"

  # Optional parameters
  local start_ts=""
  local end_ts=""
  local duration_sec=""
  local digest=""
  local retry_count=""
  local cache_hit_rate=""
  local image_size=""
  local image_size_change=""

  while [[ $# -gt 6 ]]; do
    case "$7" in
      --start)
        start_ts="$8"
        shift 2
        ;;
      --end)
        end_ts="$8"
        shift 2
        ;;
      --duration)
        duration_sec="$8"
        shift 2
        ;;
      --digest)
        digest="$8"
        shift 2
        ;;
      --retry-count)
        retry_count="$8"
        shift 2
        ;;
      --cache-hit-rate)
        cache_hit_rate="$8"
        shift 2
        ;;
      --image-size)
        image_size="$8"
        shift 2
        ;;
      --image-size-change)
        image_size_change="$8"
        shift 2
        ;;
      *)
        echo "ERROR: Unknown option: $7" >&2
        return 1
        ;;
    esac
  done

  # Validate required arguments (VERSION can be empty)
  if [[ -z "$image_dir" ]] || [[ -z "$commit" ]] || \
     [[ -z "$branch" ]] || [[ -z "$arch" ]] || [[ -z "$status" ]]; then
    echo "ERROR: Missing required arguments to append_build_record" >&2
    return 1
  fi

  # Ensure history directory exists
  local history_file="${image_dir}/history.jsonl"
  mkdir -p "$(dirname "$history_file")" || {
    echo "ERROR: Failed to create directory for history file: $history_file" >&2
    return 1
  }

  # Get current timestamp in ISO 8601 format
  local iso_timestamp
  iso_timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Check if we need to create a new record or update existing one
  # Records are grouped by version, so multiple architectures can be in same record

  if [[ -f "$history_file" ]]; then
    # Try to update existing record for this version
    local temp_file
    temp_file=$(mktemp)

    local found_match=false
    local updated_content=""

    # Read existing file line by line (JSONL format)
    while IFS= read -r line; do
      # Skip empty lines
      if [[ -z "$line" ]]; then
        continue
      fi

      # Parse the record to check if it matches our version
      local record_version
      record_version=$(echo "$line" | jq -r '.version // empty' 2>/dev/null || echo "")

      if [[ "$record_version" == "$version" ]]; then
        found_match=true
        # Update existing record with new architecture data
        line=$(echo "$line" | jq -c \
          --arg arch "$arch" \
          --arg status "$status" \
          --argjson digest "$(jq -Rn --arg d "$digest" 'if $d == "" then null else $d end')" \
          --argjson duration "$(jq -Rn --arg d "$duration_sec" 'if $d == "" then null else ($d | tonumber) end')" \
          --argjson start_ts "$(jq -Rn --arg d "$start_ts" 'if $d == "" then null else ($d | tonumber) end')" \
          --argjson end_ts "$(jq -Rn --arg d "$end_ts" 'if $d == "" then null else ($d | tonumber) end')" \
          --argjson retry_count "$(jq -Rn --arg d "$retry_count" 'if $d == "" then null else ($d | tonumber) end')" \
          --argjson cache_hit_rate "$(jq -Rn --arg d "$cache_hit_rate" 'if $d == "" then null else ($d | tonumber) end')" \
          --argjson image_size "$(jq -Rn --arg d "$image_size" 'if $d == "" then null else ($d | tonumber) end')" \
          --argjson image_size_change "$(jq -Rn --arg d "$image_size_change" 'if $d == "" then null else ($d | tonumber) end')" \
          '.architectures[$arch] = {
            "status": $status,
            "digest": $digest,
            "duration_seconds": $duration,
            "start_timestamp": $start_ts,
            "end_timestamp": $end_ts,
            "retry_count": $retry_count,
            "cache_hit_rate": $cache_hit_rate,
            "image_size": $image_size,
            "image_size_change": $image_size_change
          }' 2>/dev/null || echo "$line")
      fi

      echo "$line" >> "$temp_file"
    done < "$history_file"

    # If no matching record found, append new one
    if [[ "$found_match" == false ]]; then
      # Create new record with first architecture
      local arch_data
      arch_data=$(jq -nc \
        --arg status "$status" \
        --argjson digest "$(jq -Rn --arg d "$digest" 'if $d == "" then null else $d end')" \
        --argjson duration "$(jq -Rn --arg d "$duration_sec" 'if $d == "" then null else ($d | tonumber) end')" \
        --argjson start_ts "$(jq -Rn --arg d "$start_ts" 'if $d == "" then null else ($d | tonumber) end')" \
        --argjson end_ts "$(jq -Rn --arg d "$end_ts" 'if $d == "" then null else ($d | tonumber) end')" \
        --argjson retry_count "$(jq -Rn --arg d "$retry_count" 'if $d == "" then null else ($d | tonumber) end')" \
        --argjson cache_hit_rate "$(jq -Rn --arg d "$cache_hit_rate" 'if $d == "" then null else ($d | tonumber) end')" \
        --argjson image_size "$(jq -Rn --arg d "$image_size" 'if $d == "" then null else ($d | tonumber) end')" \
        --argjson image_size_change "$(jq -Rn --arg d "$image_size_change" 'if $d == "" then null else ($d | tonumber) end')" \
        '{
          "status": $status,
          "digest": $digest,
          "duration_seconds": $duration,
          "start_timestamp": $start_ts,
          "end_timestamp": $end_ts,
          "retry_count": $retry_count,
          "cache_hit_rate": $cache_hit_rate,
          "image_size": $image_size,
          "image_size_change": $image_size_change
        }') || {
        echo "ERROR: Failed to create arch_data JSON (existing file path)" >&2
        rm -f "$temp_file"
        return 1
      }

      if [[ -z "$arch_data" ]]; then
        echo "ERROR: arch_data is empty (existing file path)" >&2
        rm -f "$temp_file"
        return 1
      fi

      local new_record
      new_record=$(jq -nc \
        --arg version "$version" \
        --arg timestamp "$iso_timestamp" \
        --arg commit "$commit" \
        --arg branch "$branch" \
        --arg arch "$arch" \
        --argjson arch_data "$arch_data" \
        '{
          "version": $version,
          "timestamp": $timestamp,
          "commit": $commit,
          "branch": $branch,
          "manual_trigger": false,
          "trigger_overrides": null,
          "architectures": {
            ($arch): $arch_data
          }
        }') || {
        echo "ERROR: Failed to create new_record JSON (existing file path)" >&2
        rm -f "$temp_file"
        return 1
      }

      if [[ -z "$new_record" ]]; then
        echo "ERROR: new_record is empty (existing file path)" >&2
        rm -f "$temp_file"
        return 1
      fi

      echo "$new_record" >> "$temp_file"
    fi

    # Replace original file with updated version
    mv "$temp_file" "$history_file" || {
      echo "ERROR: Failed to write history file: $history_file" >&2
      rm -f "$temp_file"
      return 1
    }
  else
    # Create new history file with first record
    local arch_data
    arch_data=$(jq -nc \
      --arg status "$status" \
      --argjson digest "$(jq -Rn --arg d "$digest" 'if $d == "" then null else $d end')" \
      --argjson duration "$(jq -Rn --arg d "$duration_sec" 'if $d == "" then null else ($d | tonumber) end')" \
      --argjson start_ts "$(jq -Rn --arg d "$start_ts" 'if $d == "" then null else ($d | tonumber) end')" \
      --argjson end_ts "$(jq -Rn --arg d "$end_ts" 'if $d == "" then null else ($d | tonumber) end')" \
      --argjson retry_count "$(jq -Rn --arg d "$retry_count" 'if $d == "" then null else ($d | tonumber) end')" \
      --argjson cache_hit_rate "$(jq -Rn --arg d "$cache_hit_rate" 'if $d == "" then null else ($d | tonumber) end')" \
      --argjson image_size "$(jq -Rn --arg d "$image_size" 'if $d == "" then null else ($d | tonumber) end')" \
      --argjson image_size_change "$(jq -Rn --arg d "$image_size_change" 'if $d == "" then null else ($d | tonumber) end')" \
      '{
        "status": $status,
        "digest": $digest,
        "duration_seconds": $duration,
        "start_timestamp": $start_ts,
        "end_timestamp": $end_ts,
        "retry_count": $retry_count,
        "cache_hit_rate": $cache_hit_rate,
        "image_size": $image_size,
        "image_size_change": $image_size_change
      }') || {
      echo "ERROR: Failed to create arch_data JSON (new file path)" >&2
      return 1
    }

    if [[ -z "$arch_data" ]]; then
      echo "ERROR: arch_data is empty (new file path)" >&2
      return 1
    fi

    local new_record
    new_record=$(jq -nc \
      --arg version "$version" \
      --arg timestamp "$iso_timestamp" \
      --arg commit "$commit" \
      --arg branch "$branch" \
      --arg arch "$arch" \
      --argjson arch_data "$arch_data" \
      '{
        "version": $version,
        "timestamp": $timestamp,
        "commit": $commit,
        "branch": $branch,
        "manual_trigger": false,
        "trigger_overrides": null,
        "architectures": {
          ($arch): $arch_data
        }
      }') || {
      echo "ERROR: Failed to create new_record JSON (new file path)" >&2
      return 1
    }

    if [[ -z "$new_record" ]]; then
      echo "ERROR: new_record is empty (new file path)" >&2
      return 1
    fi

    echo "$new_record" > "$history_file" || {
      echo "ERROR: Failed to write to history file: $history_file" >&2
      return 1
    }
  fi

  return 0
}

# query_build_duration: Query build duration for an image
#
# Arguments:
#   IMAGE_DIR: Image directory name
#   [--arch ARCH]: Filter by architecture (optional, defaults to amd64)
#   [--version VERSION]: Filter by specific version (optional)
#   [--last N]: Get last N records (optional)
#
# Output: JSON records matching query
#
query_build_duration() {
  local image_dir="$1"
  local arch="amd64"
  local version=""
  local last=0

  shift || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --arch)
        arch="$2"
        shift 2
        ;;
      --version)
        version="$2"
        shift 2
        ;;
      --last)
        last="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done

  local history_file="${image_dir}/history.jsonl"

  if [[ ! -f "$history_file" ]]; then
    echo "ERROR: History file not found: $history_file" >&2
    return 1
  fi

  # Build jq filter
  local filter='.architectures["'$arch'"].duration_seconds // null'
  if [[ -n "$version" ]]; then
    filter="select(.version == \"$version\") | $filter"
  fi

  if [[ $last -gt 0 ]]; then
    jq -r "$filter" "$history_file" | tail -"$last"
  else
    jq -r "$filter" "$history_file"
  fi
}

# calculate_average_duration: Calculate average build duration
#
# Arguments:
#   IMAGE_DIR: Image directory name
#   [--arch ARCH]: Filter by architecture (optional, defaults to amd64)
#   [--last N]: Average over last N records (optional)
#
# Output: Average duration in seconds
#
calculate_average_duration() {
  local image_dir="$1"
  local arch="amd64"
  local last=10

  shift || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --arch)
        arch="$2"
        shift 2
        ;;
      --last)
        last="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done

  local history_file="${image_dir}/history.jsonl"

  if [[ ! -f "$history_file" ]]; then
    echo "ERROR: History file not found: $history_file" >&2
    return 1
  fi

  jq -r '.architectures["'$arch'"].duration_seconds // empty' "$history_file" | \
    tail -"$last" | \
    awk '{sum+=$1; count++} END {if(count>0) printf "%.1f\n", sum/count; else print "No data"}'
}

# update_manual_trigger: Mark a record as manually triggered (Sprint 13)
#
# Arguments:
#   IMAGE_DIR: Image directory name
#   VERSION: Version string to update
#   [--overrides OVERRIDES_JSON]: Optional JSON object with override details
#
# Updates the record for the given version to set manual_trigger=true and optionally add trigger_overrides
#
update_manual_trigger() {
  local image_dir="$1"
  local version="$2"
  local overrides=""

  shift 2 || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --overrides)
        overrides="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done

  local history_file="${image_dir}/history.jsonl"

  if [[ ! -f "$history_file" ]]; then
    echo "ERROR: History file not found: $history_file" >&2
    return 1
  fi

  local temp_file
  temp_file=$(mktemp)

  # Update matching records
  while IFS= read -r line; do
    local record_version
    record_version=$(echo "$line" | jq -r '.version // empty' 2>/dev/null || echo "")

    if [[ "$record_version" == "$version" ]]; then
      if [[ -n "$overrides" ]]; then
        line=$(echo "$line" | jq \
          --argjson overrides "$overrides" \
          '.manual_trigger = true | .trigger_overrides = $overrides')
      else
        line=$(echo "$line" | jq '.manual_trigger = true')
      fi
    fi

    echo "$line" >> "$temp_file"
  done < "$history_file"

  # Replace original file
  mv "$temp_file" "$history_file" || {
    echo "ERROR: Failed to write history file: $history_file" >&2
    rm -f "$temp_file"
    return 1
  }

  return 0
}

export -f append_build_record
export -f query_build_duration
export -f calculate_average_duration
export -f update_manual_trigger
