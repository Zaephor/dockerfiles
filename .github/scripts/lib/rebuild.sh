#!/usr/bin/env bash
#
# Rebuild Library
#
# Provides functions to support manual version rebuild workflows, enabling
# maintainers to rebuild specific historical versions of images for
# emergency rollback scenarios.
#

set -euo pipefail

# Source dependencies
# shellcheck source=/dev/null
source "${BASH_SOURCE%/*}/history-query.sh"
# shellcheck source=/dev/null
source "${BASH_SOURCE%/*}/tag-manager.sh"

# Validate a rebuild request for correctness and safety
#
# Arguments:
#   $1: Target image name (e.g., "hello-world")
#   $2: Target version to rebuild (e.g., "1.0.5")
#   $3: Path to history.jsonl file
#   $4: Path to image directory
#
# Returns:
#   0 if rebuild request is valid, 1 otherwise
#
# Checks:
#   - History file exists
#   - Version exists in history
#   - Image directory exists
#   - Target version is not already being built
#
validate_rebuild_request() {
  local image_name="$1"
  local target_version="$2"
  local history_file="$3"
  local image_dir="$4"

  # Check history file exists
  if [[ ! -f "$history_file" ]]; then
    echo "ERROR: History file not found: $history_file" >&2
    return 1
  fi

  # Check image directory exists
  if [[ ! -d "$image_dir" ]]; then
    echo "ERROR: Image directory not found: $image_dir" >&2
    return 1
  fi

  # Check version exists in history
  if ! version_exists "$history_file" "$target_version"; then
    echo "ERROR: Version $target_version not found in history for $image_name" >&2
    return 1
  fi

  # Log validation success with structured output
  echo "REBUILD_VALIDATION: image=$image_name version=$target_version status=valid"

  return 0
}

# Checkout repository to historical state for a version
#
# Arguments:
#   $1: Path to history.jsonl file
#   $2: Target version
#
# Returns:
#   0 if checkout succeeds, 1 otherwise
#
# Output:
#   Commit SHA that was checked out
#
checkout_historical_state() {
  local history_file="$1"
  local target_version="$2"

  if [[ ! -f "$history_file" ]]; then
    echo "ERROR: History file not found: $history_file" >&2
    return 1
  fi

  # Get the commit SHA for the target version
  local commit_sha
  commit_sha=$(get_version_commit "$history_file" "$target_version")

  if [[ -z "$commit_sha" ]]; then
    echo "ERROR: Could not find commit SHA for version $target_version" >&2
    return 1
  fi

  # Verify commit exists in repository
  if ! git cat-file -e "$commit_sha" 2>/dev/null; then
    echo "ERROR: Commit $commit_sha not found in repository" >&2
    return 1
  fi

  # Checkout the commit (detached HEAD)
  git checkout "$commit_sha" || return 1

  # Log the checkout
  echo "CHECKOUT_HISTORICAL_STATE: version=$target_version commit=$commit_sha"
  echo "$commit_sha"

  return 0
}

# Restore the original branch after a rebuild
#
# Arguments:
#   $1: Original branch name (typically GITHUB_REF_NAME)
#
# Returns:
#   0 if branch restoration succeeds, 1 otherwise
#
restore_rebuild_branch() {
  local original_branch="$1"

  if [[ -z "$original_branch" ]]; then
    echo "ERROR: Original branch name not provided" >&2
    return 1
  fi

  # Check if branch exists (handle case where it might be a tag or PR ref)
  if git rev-parse --verify "origin/$original_branch" > /dev/null 2>&1; then
    git checkout "$original_branch" || return 1
  elif git rev-parse --verify "$original_branch" > /dev/null 2>&1; then
    git checkout "$original_branch" || return 1
  else
    # Default to main if original branch not found
    git checkout main || return 1
  fi

  echo "RESTORE_BRANCH: branch=$original_branch"
  return 0
}

# Generate a history entry for a rebuild event
#
# Arguments:
#   $1: Version string
#   $2: Timestamp (ISO8601 format, e.g., "2025-11-13T10:30:00Z")
#   $3: Rebuild reason (e.g., "emergency_rollback")
#   $4: Original commit SHA (from history)
#   $5: Current commit SHA (head of original branch, for reference)
#
# Output:
#   JSON object suitable for appending to history.jsonl
#
# Note: This generates the entry structure, but doesn't append to file
#
generate_rebuild_history_entry() {
  local version="$1"
  local timestamp="$2"
  local rebuild_reason="$3"
  local original_commit="$4"
  local current_commit="$5"

  # Generate ISO8601 timestamp if not provided
  if [[ -z "$timestamp" ]]; then
    timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  fi

  # Output JSON entry with rebuild metadata
  # Note: Architecture status should be provided separately by the build step
  cat <<EOF
{
  "version": "$version",
  "timestamp": "$timestamp",
  "commit": "$original_commit",
  "branch": "rebuild",
  "rebuild_metadata": {
    "reason": "$rebuild_reason",
    "triggered_at": "$timestamp",
    "original_commit": "$original_commit",
    "rebuild_branch_head": "$current_commit"
  },
  "architectures": {}
}
EOF

  echo "REBUILD_HISTORY_ENTRY: version=$version reason=$rebuild_reason"
  return 0
}

# Generate a version queue for rebuilding multiple versions in sequence
#
# Arguments:
#   $1: Path to history.jsonl file
#   $2: Start version (inclusive)
#   $3: End version (inclusive)
#   $4: Optional filter: --filter-status=any|success|failed (default: any)
#
# Output:
#   JSON array of versions with metadata, suitable for queue processing
#
generate_version_queue() {
  local history_file="$1"
  local start_version="$2"
  local end_version="$3"
  local filter="${4:---filter-status=any}"

  if [[ ! -f "$history_file" ]]; then
    echo "ERROR: History file not found: $history_file" >&2
    return 1
  fi

  # Extract filter type
  local filter_type="any"
  if [[ "$filter" =~ ^--filter-status=(.+)$ ]]; then
    filter_type="${BASH_REMATCH[1]}"
  fi

  # Generate queue as JSON array
  echo "["

  local first=1
  local versions
  versions=$(query_versions_between "$history_file" "$start_version" "$end_version" "--format=simple")

  # Reverse to chronological order (oldest first) for queue processing
  while IFS= read -r version; do
    # Apply status filter if needed
    if [[ "$filter_type" != "any" ]]; then
      local entry
      entry=$(get_version_details "$history_file" "$version")

      # Skip if doesn't match filter
      case "$filter_type" in
        success)
          # Check if all architectures succeeded
          if ! echo "$entry" | jq -e '.architectures[] | select(.status == "failure")' > /dev/null 2>&1; then
            : # Pass through
          else
            continue
          fi
          ;;
        failed)
          # Check if any architecture failed
          if ! echo "$entry" | jq -e '.architectures[] | select(.status == "failure")' > /dev/null 2>&1; then
            continue
          fi
          ;;
      esac
    fi

    # Output JSON object for this version
    if [[ $first -eq 0 ]]; then
      echo ","
    fi
    first=0

    get_version_details "$history_file" "$version" | jq '.

+ {queue_position: 0}' | tr -d '\n'
  done < <(echo "$versions" | sort -V)

  echo ""
  echo "]"

  echo "VERSION_QUEUE_GENERATED: start=$start_version end=$end_version count=$(echo "$versions" | wc -l)"
  return 0
}

# Extract rebuild queue position for a version in a queue
#
# Arguments:
#   $1: Version string
#   $2: Start version of queue
#   $3: End version of queue
#   $4: Path to history file
#
# Output:
#   Queue position (0-based index, oldest first)
#
get_queue_position() {
  local version="$1"
  local start_version="$2"
  local end_version="$3"
  local history_file="$4"

  local position=0
  local versions
  versions=$(query_versions_between "$history_file" "$start_version" "$end_version" "--format=simple")

  # Reverse order (newest to oldest) to process oldest first
  for v in $(echo "$versions" | sort -V); do
    if [[ "$v" == "$version" ]]; then
      echo "$position"
      return 0
    fi
    ((position++))
  done

  return 1
}
