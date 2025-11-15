#!/usr/bin/env bash
# merge-history-artifacts.sh - Intelligently merge history artifacts
#
# This script merges history artifacts from parallel builds by:
# 1. Combining records with the same version
# 2. Merging architecture data into single records
# 3. Avoiding duplicates

set -euo pipefail

ARTIFACTS_DIR="${1:-/tmp/history-artifacts}"

echo "Merging history files from artifacts..."

# Track which images we've processed
declare -A processed_images

for artifact_dir in "$ARTIFACTS_DIR"/history-*; do
  if [ ! -d "$artifact_dir" ]; then
    continue
  fi

  artifact_name=$(basename "$artifact_dir")
  echo "Processing artifact: $artifact_name"

  # Read the image path from metadata
  image_path_file="$artifact_dir/image_path.txt"
  history_file="$artifact_dir/history.jsonl"

  if [ ! -f "$image_path_file" ]; then
    echo "  WARNING: No image_path.txt in $artifact_name"
    continue
  fi

  if [ ! -f "$history_file" ]; then
    echo "  WARNING: No history.jsonl in $artifact_name"
    continue
  fi

  # Read the image directory path
  image_dir=$(cat "$image_path_file")
  echo "  Image directory: $image_dir"

  target_file="${image_dir}/history.jsonl"
  mkdir -p "$(dirname "$target_file")"

  # Mark this image as processed
  processed_images["$image_dir"]=1

  # Append to a temp aggregation file for this image
  temp_agg="/tmp/history-agg-${image_dir//\//_}.jsonl"
  cat "$history_file" >> "$temp_agg"
done

echo ""
echo "Merging duplicate records by version..."

# Now process each image's aggregated file
for image_dir in "${!processed_images[@]}"; do
  temp_agg="/tmp/history-agg-${image_dir//\//_}.jsonl"
  target_file="${image_dir}/history.jsonl"

  if [ ! -f "$temp_agg" ]; then
    continue
  fi

  echo "Processing $image_dir:"

  # Use jq to merge records with the same version
  # Group by version, then merge architectures
  jq -sc '
    # Group by version
    group_by(.version) |
    # For each group, merge all architecture data
    map({
      version: .[0].version,
      timestamp: .[0].timestamp,
      commit: .[0].commit,
      branch: .[0].branch,
      manual_trigger: .[0].manual_trigger,
      trigger_overrides: .[0].trigger_overrides,
      # Merge all architectures from all records in this group
      architectures: (map(.architectures) | add)
    })[]
  ' "$temp_agg" > "$target_file"

  line_count=$(wc -l < "$target_file")
  echo "  Merged into $line_count unique version(s)"

  # Clean up temp file
  rm -f "$temp_agg"
done

echo ""
echo "History merge complete. Updated files:"
find . -name 'history.jsonl' -type f | while read -r f; do
  echo "  $f ($(wc -l < "$f") lines)"
done
