#!/usr/bin/env bash
# record-build-history.sh - Record build history with metrics
#
# Usage:
#   record-build-history.sh \
#     --image-dir IMAGE_DIR \
#     --version VERSION \
#     --commit COMMIT \
#     --branch BRANCH \
#     --arch ARCH \
#     --build-status STATUS \
#     [--build-start START] \
#     [--build-end END] \
#     [--duration DURATION] \
#     [--digest DIGEST] \
#     [--retry-count COUNT] \
#     [--cache-hit-rate RATE] \
#     [--image-size SIZE]
#
# Description:
#   Records build history with performance metrics to the image's history.jsonl file.
#   Supports graceful degradation when optional metrics are not available.
#
# Exit Codes:
#   0 - Success
#   1 - Failed to record history

set -euo pipefail

# Script metadata
# shellcheck disable=SC2034
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries
# shellcheck source=lib/history.sh
source "$SCRIPT_DIR/lib/history.sh"
# shellcheck source=lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"

# Global variables
IMAGE_DIR=""
VERSION=""
COMMIT=""
BRANCH=""
ARCH=""
BUILD_STATUS=""
BUILD_START=""
BUILD_END=""
DURATION=""
BUILD_DIGEST=""
RETRY_COUNT="0"
CACHE_HIT_RATE=""
IMAGE_SIZE=""

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --image-dir)
            IMAGE_DIR="$2"
            shift 2
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --commit)
            COMMIT="$2"
            shift 2
            ;;
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --build-status)
            BUILD_STATUS="$2"
            shift 2
            ;;
        --build-start)
            BUILD_START="$2"
            shift 2
            ;;
        --build-end)
            BUILD_END="$2"
            shift 2
            ;;
        --duration)
            DURATION="$2"
            shift 2
            ;;
        --digest)
            BUILD_DIGEST="$2"
            shift 2
            ;;
        --retry-count)
            RETRY_COUNT="$2"
            shift 2
            ;;
        --cache-hit-rate)
            CACHE_HIT_RATE="$2"
            shift 2
            ;;
        --image-size)
            IMAGE_SIZE="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown parameter: $1" >&2
            exit 1
            ;;
    esac
done

# Validate required parameters (VERSION can be empty)
if [ -z "$IMAGE_DIR" ] || [ -z "$COMMIT" ] || [ -z "$BRANCH" ] || [ -z "$ARCH" ] || [ -z "$BUILD_STATUS" ]; then
    echo "Error: Missing required parameters" >&2
    exit 1
fi

# Graceful degradation: Use null if timestamps or duration missing
if [ -z "$BUILD_START" ] || [ -z "$BUILD_END" ] || [ -z "$DURATION" ]; then
    log_warning "$IMAGE_DIR" "$ARCH" "HISTORY" "Timestamps missing or invalid (graceful degradation)"
    DURATION=""
    BUILD_START=""
    BUILD_END=""
fi

# Call append_build_record with all metrics including retry count, cache_hit_rate, and image_size
append_build_record "$IMAGE_DIR" "$VERSION" "$COMMIT" "$BRANCH" "$ARCH" "$BUILD_STATUS" \
    --start "$BUILD_START" \
    --end "$BUILD_END" \
    --duration "$DURATION" \
    --digest "$BUILD_DIGEST" \
    --retry-count "$RETRY_COUNT" \
    --cache-hit-rate "$CACHE_HIT_RATE" \
    --image-size "$IMAGE_SIZE" || {
    log_warning "$IMAGE_DIR" "$ARCH" "HISTORY" "Failed to update history file (non-fatal, continuing)"
}

log_structured "$IMAGE_DIR" "$ARCH" "HISTORY" "History recorded with retry_count=$RETRY_COUNT, cache_hit_rate=$CACHE_HIT_RATE, image_size=$IMAGE_SIZE, build_status=$BUILD_STATUS"
