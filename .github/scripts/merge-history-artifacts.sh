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

# Track which image+variant combinations we've processed
declare -A processed_targets

for artifact_dir in "$ARTIFACTS_DIR"/history-*; do
  if [ ! -d "$artifact_dir" ]; then
    continue
  fi

  artifact_name=$(basename "$artifact_dir")
  echo "Processing artifact: $artifact_name"

  # Read the image path and variant from metadata
  image_path_file="$artifact_dir/image_path.txt"
  variant_file="$artifact_dir/variant.txt"
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

  # Read variant (may not exist for older artifacts)
  variant=""
  if [ -f "$variant_file" ]; then
    variant=$(cat "$variant_file")
  fi

  echo "  Image directory: $image_dir"
  echo "  Variant: ${variant:-default}"

  # Determine target file based on variant
  if [ -z "$variant" ] || [ "$variant" = "default" ]; then
    target_file="${image_dir}/history.jsonl"
    target_key="${image_dir}"
  else
    target_file="${image_dir}/history-${variant}.jsonl"
    target_key="${image_dir}::${variant}"
  fi

  mkdir -p "$(dirname "$target_file")"

  # Mark this image+variant as processed
  processed_targets["$target_key"]="$target_file"

  # Append to a temp aggregation file for this image+variant
  temp_agg="/tmp/history-agg-${target_key//[\/:]/_}.jsonl"
  cat "$history_file" >> "$temp_agg"
done

echo ""
echo "Merging duplicate records by version..."

# Now process each image+variant's aggregated file
for target_key in "${!processed_targets[@]}"; do
  target_file="${processed_targets[$target_key]}"
  temp_agg="/tmp/history-agg-${target_key//[\/:]/_}.jsonl"

  if [ ! -f "$temp_agg" ]; then
    continue
  fi

  echo "Processing $target_key -> $(basename "$target_file"):"

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
find . \( -name 'history.jsonl' -o -name 'history-*.jsonl' \) -type f | while read -r f; do
  echo "  $f ($(wc -l < "$f") lines)"
done
