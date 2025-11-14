#!/usr/bin/env bash
# generate-dryrun-report.sh - Generate dry-run summary report
#
# Usage:
#   generate-dryrun-report.sh --matrix MATRIX_JSON
#
# Description:
#   Generates a summary report for dry-run builds, displaying which images
#   would be built without actually executing the builds. Outputs to
#   GitHub Actions step summary.
#
# Exit Codes:
#   0 - Success

set -euo pipefail

# Script metadata
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries
# shellcheck source=lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"

# Global variables
MATRIX=""

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --matrix)
            MATRIX="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown parameter: $1" >&2
            echo "Usage: $SCRIPT_NAME --matrix MATRIX_JSON" >&2
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$MATRIX" ]; then
    echo "Error: Missing required parameter --matrix" >&2
    echo "Usage: $SCRIPT_NAME --matrix MATRIX_JSON" >&2
    exit 1
fi

# shellcheck disable=SC2129
echo "## Dry-Run Analysis Report" >> "$GITHUB_STEP_SUMMARY"
echo "" >> "$GITHUB_STEP_SUMMARY"

# Check if matrix is empty
if [ "$MATRIX" = '{"image":[]}' ] || [ -z "$MATRIX" ]; then
    echo "✓ **No images require building**" >> "$GITHUB_STEP_SUMMARY"
    echo "" >> "$GITHUB_STEP_SUMMARY"
    echo "All images are up to date. No changes detected." >> "$GITHUB_STEP_SUMMARY"
    log_notice "SYSTEM" "-" "DRY_RUN" "Dry-run completed: No images require building"
    exit 0
fi

# Parse and display images that would be built
IMAGE_COUNT=$(echo "$MATRIX" | jq '.image | length')
echo "📊 **Images to Build: $IMAGE_COUNT**" >> "$GITHUB_STEP_SUMMARY"
echo "" >> "$GITHUB_STEP_SUMMARY"

echo "| Image | Version | Reason |" >> "$GITHUB_STEP_SUMMARY"
echo "|-------|---------|--------|" >> "$GITHUB_STEP_SUMMARY"

# Extract and format each image
echo "$MATRIX" | jq -r '.image[] | "| \(.name) | \(.version) | \(.reason) |"' >> "$GITHUB_STEP_SUMMARY"

echo "" >> "$GITHUB_STEP_SUMMARY"
echo "### Dry-Run Details" >> "$GITHUB_STEP_SUMMARY"
echo "- **Mode**: Dry-run (no builds will execute)" >> "$GITHUB_STEP_SUMMARY"
echo "- **Timestamp**: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$GITHUB_STEP_SUMMARY"
echo "- **Branch**: ${GITHUB_REF_NAME:-unknown}" >> "$GITHUB_STEP_SUMMARY"
echo "- **Commit**: ${GITHUB_SHA:-unknown}" >> "$GITHUB_STEP_SUMMARY"

log_notice "SYSTEM" "-" "DRY_RUN" "Dry-run completed: $IMAGE_COUNT images would build"
