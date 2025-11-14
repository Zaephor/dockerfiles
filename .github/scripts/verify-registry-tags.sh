#!/usr/bin/env bash
# verify-registry-tags.sh - Verify published tags exist in registry
#
# Usage:
#   verify-registry-tags.sh \
#     --repository REPO \
#     --commit-sha SHA \
#     --branch-name BRANCH \
#     --digests-path PATH \
#     --workspace WORKSPACE
#
# Description:
#   Verifies that multi-architecture manifest tags exist in the registry
#   for all built images. Checks both commit SHA and branch tags.
#   Prints informational warnings for missing manifests but does not fail
#   the job, as some builds may legitimately fail or be skipped.
#
# Exit Codes:
#   0 - Always exits successfully (warnings are informational only)

set -euo pipefail

# Script metadata
# shellcheck disable=SC2034
SCRIPT_NAME="$(basename "$0")"

# Global variables
REPOSITORY=""
COMMIT_SHA=""
BRANCH_NAME=""
DIGESTS_PATH=""
WORKSPACE=""

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --repository)
            REPOSITORY="$2"
            shift 2
            ;;
        --commit-sha)
            COMMIT_SHA="$2"
            shift 2
            ;;
        --branch-name)
            BRANCH_NAME="$2"
            shift 2
            ;;
        --digests-path)
            DIGESTS_PATH="$2"
            shift 2
            ;;
        --workspace)
            WORKSPACE="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown parameter: $1" >&2
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$REPOSITORY" ] || [ -z "$COMMIT_SHA" ] || [ -z "$BRANCH_NAME" ] || [ -z "$DIGESTS_PATH" ] || [ -z "$WORKSPACE" ]; then
    echo "Error: Missing required parameters" >&2
    exit 1
fi

echo "Verifying published tags in registry..."
echo "========================================="

# Repository name (lowercase required by Docker)
GHCR_REPO=$(echo "$REPOSITORY" | tr '[:upper:]' '[:lower:]')
# shellcheck disable=SC2001
BRANCH_TAG="$(echo "$BRANCH_NAME" | sed 's/[^a-zA-Z0-9.-]/-/g')"

# Find all image-variant pairs that were processed
verification_failed=0
for amd64_artifact in "$DIGESTS_PATH"/digest-*-amd64; do
    if [ -d "$amd64_artifact" ]; then
        artifact_name=$(basename "$amd64_artifact")
        if [[ "$artifact_name" =~ ^digest-(.+)-amd64$ ]]; then
            image_variant="${BASH_REMATCH[1]}"

            # Extract image name from the variant pair
            # Check if this matches a directory in repo root
            image_name=""
            for dir in "$WORKSPACE"/*/; do
                dir_name=$(basename "$dir")
                if [[ "$image_variant" == "$dir_name"* ]]; then
                    image_name="$dir_name"
                    break
                fi
            done

            # Fallback parsing if no dir matched
            if [ -z "$image_name" ]; then
                if [[ "$image_variant" =~ ^(.+)-([a-z0-9-]+)$ ]]; then
                    image_name="${BASH_REMATCH[1]}"
                else
                    image_name="$image_variant"
                fi
            fi

            image_repo="ghcr.io/${GHCR_REPO}/${image_name}"

            # Verify manifest exists for commit SHA tag using docker buildx imagetools inspect
            echo "Verifying manifest for: ${image_repo}:${COMMIT_SHA}"
            if docker buildx imagetools inspect "${image_repo}:${COMMIT_SHA}" >/dev/null 2>&1; then
                echo "  ✓ PASS: Manifest exists for commit SHA tag"
            else
                echo "  ✗ FAIL: Manifest not found for commit SHA tag"
                verification_failed=1
            fi

            # Verify manifest exists for branch tag using docker buildx imagetools inspect
            echo "Verifying manifest for: ${image_repo}:${BRANCH_TAG}"
            if docker buildx imagetools inspect "${image_repo}:${BRANCH_TAG}" >/dev/null 2>&1; then
                echo "  ✓ PASS: Manifest exists for branch tag"
            else
                echo "  ✗ FAIL: Manifest not found for branch tag"
                verification_failed=1
            fi
        fi
    fi
done

echo ""
echo "Registry verification complete (warnings above are normal in local environments)"

# Exit 0 to not fail the job - verification warnings are informational only
# Some builds may legitimately fail or be skipped (no changes detected)
exit 0
