#!/usr/bin/env bash
# verify-registry-push.sh - Verify Docker image push to registry with retry logic
#
# Usage:
#   verify-registry-push.sh \
#     --image-repo IMAGE_REPO \
#     --arch ARCH \
#     --image-name IMAGE_NAME \
#     --build-metadata BUILD_METADATA
#
# Description:
#   Verifies that a Docker image was successfully pushed to the registry by
#   inspecting the image digest. Includes exponential backoff retry logic
#   for handling transient registry failures.
#
# Exit Codes:
#   0 - Registry verification succeeded
#   1 - Registry verification failed after all retries

set -euo pipefail

# Script metadata
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries
# shellcheck source=lib/retry-logic.sh
source "$SCRIPT_DIR/lib/retry-logic.sh"
# shellcheck source=lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"

# Global variables
IMAGE_REPO=""
ARCH=""
IMAGE_NAME=""
BUILD_METADATA=""

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --image-repo)
            IMAGE_REPO="$2"
            shift 2
            ;;
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --image-name)
            IMAGE_NAME="$2"
            shift 2
            ;;
        --build-metadata)
            BUILD_METADATA="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown parameter: $1" >&2
            echo "Usage: $SCRIPT_NAME --image-repo REPO --arch ARCH --image-name NAME --build-metadata FILE" >&2
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$IMAGE_REPO" ] || [ -z "$ARCH" ] || [ -z "$IMAGE_NAME" ] || [ -z "$BUILD_METADATA" ]; then
    echo "Error: Missing required parameters" >&2
    echo "Usage: $SCRIPT_NAME --image-repo REPO --arch ARCH --image-name NAME --build-metadata FILE" >&2
    exit 1
fi

# Extract digest from buildx metadata for push verification
if [ ! -f "$BUILD_METADATA" ]; then
    log_error "$IMAGE_NAME" "$ARCH" "REGISTRY_PUSH" "Build metadata file not found: $BUILD_METADATA"
    exit 1
fi

# Get digest to track successful push
DIGEST=$(jq -r '."containerimage.digest"' "$BUILD_METADATA")
if [[ ! "$DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    log_error "$IMAGE_NAME" "$ARCH" "REGISTRY_PUSH" "Invalid digest format: $DIGEST"
    exit 1
fi

log_structured "$IMAGE_NAME" "$ARCH" "REGISTRY_PUSH" "Verifying push to registry (digest: ${DIGEST:0:12}...)"

# Verify push was successful by checking registry
# We use docker buildx imagetools inspect to verify the image exists in registry
# This is a lightweight verification that can be retried on transient failures
retry_attempt=0
max_retry_attempts=2
retry_delay=30

while [ $retry_attempt -lt $max_retry_attempts ]; do
    retry_attempt=$((retry_attempt + 1))
    log_structured "$IMAGE_NAME" "$ARCH" "REGISTRY_PUSH" "Registry verification attempt $retry_attempt/$max_retry_attempts"

    # Attempt to inspect the pushed image to verify it exists in registry
    # Show error output on first attempt for debugging
    if [ $retry_attempt -eq 1 ]; then
        if docker buildx imagetools inspect "${IMAGE_REPO}@${DIGEST}" 2>&1; then
            log_structured "$IMAGE_NAME" "$ARCH" "REGISTRY_PUSH" "Registry verification succeeded on attempt $retry_attempt"
            echo "retry_attempts=$((retry_attempt - 1))" >> "$GITHUB_OUTPUT"
            exit 0
        fi
    else
        if docker buildx imagetools inspect "${IMAGE_REPO}@${DIGEST}" > /dev/null 2>&1; then
            log_structured "$IMAGE_NAME" "$ARCH" "REGISTRY_PUSH" "Registry verification succeeded on attempt $retry_attempt"
            echo "retry_attempts=$((retry_attempt - 1))" >> "$GITHUB_OUTPUT"
            exit 0
        fi
    fi

    if [ $retry_attempt -lt $max_retry_attempts ]; then
        log_warning "$IMAGE_NAME" "$ARCH" "REGISTRY_PUSH" "Registry verification failed, retrying in ${retry_delay}s..."
        sleep "$retry_delay"
        retry_delay=$((retry_delay * 2))
        if [ $retry_delay -gt 300 ]; then
            retry_delay=300
        fi
    fi
done

log_error "$IMAGE_NAME" "$ARCH" "REGISTRY_PUSH" "Registry verification exhausted all $max_retry_attempts attempts"
echo "retry_attempts=$((max_retry_attempts - 1))" >> "$GITHUB_OUTPUT"
exit 1
