#!/usr/bin/env bash
# build-image.sh - Build Docker image with proper label and cache handling
#
# Usage:
#   build-image.sh \
#     --image-name IMAGE \
#     --platform PLATFORM \
#     --dockerfile DOCKERFILE \
#     --variant VARIANT \
#     --arch ARCH \
#     --image-repo REPO \
#     --cache-tag CACHE \
#     --source-url URL \
#     --revision SHA
#
# Description:
#   Builds a Docker image using buildx with proper caching, labels, and
#   push-by-digest.
#
# Exit Codes:
#   0 - Success
#   1 - Invalid parameters or build failure

set -euo pipefail

# Script metadata
SCRIPT_NAME="$(basename "$0")"

# Global variables (populated by parameter parsing)
IMAGE_NAME=""
PLATFORM=""
DOCKERFILE=""
VARIANT=""
ARCH=""
IMAGE_REPO=""
CACHE_TAG=""
SOURCE_URL=""
REVISION=""
VERSION=""

#######################################
# Print error message and exit
# Arguments:
#   $1 - Error message
#   $2 - Exit code (default: 1)
#######################################
error() {
  local message="$1"
  local exit_code="${2:-1}"
  echo "ERROR: ${message}" >&2
  exit "$exit_code"
}

#######################################
# Parse command-line arguments
#######################################
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --image-name)
        IMAGE_NAME="$2"
        shift 2
        ;;
      --platform)
        PLATFORM="$2"
        shift 2
        ;;
      --dockerfile)
        DOCKERFILE="$2"
        shift 2
        ;;
      --variant)
        VARIANT="$2"
        shift 2
        ;;
      --arch)
        ARCH="$2"
        shift 2
        ;;
      --image-repo)
        IMAGE_REPO="$2"
        shift 2
        ;;
      --cache-tag)
        CACHE_TAG="$2"
        shift 2
        ;;
      --source-url)
        SOURCE_URL="$2"
        shift 2
        ;;
      --revision)
        REVISION="$2"
        shift 2
        ;;
      --version)
        VERSION="$2"
        shift 2
        ;;
      *)
        error "Unknown option: $1" 1
        ;;
    esac
  done

  # Validate required parameters
  [[ -z "$IMAGE_NAME" ]] && error "--image-name is required"
  [[ -z "$PLATFORM" ]] && error "--platform is required"
  [[ -z "$DOCKERFILE" ]] && error "--dockerfile is required"
  [[ -z "$ARCH" ]] && error "--arch is required"
  [[ -z "$IMAGE_REPO" ]] && error "--image-repo is required"
  [[ -z "$CACHE_TAG" ]] && error "--cache-tag is required"
  [[ -z "$SOURCE_URL" ]] && error "--source-url is required"
  [[ -z "$REVISION" ]] && error "--revision is required"
  return 0
}

#######################################
# Build Docker image with buildx
#######################################
build_image() {
  echo "Building image: ${IMAGE_NAME} (${PLATFORM})"

  # Build cache scope (unique per image+arch+variant)
  local cache_scope="buildx-${IMAGE_NAME}-${ARCH}-${VARIANT}"

  # Prepare buildx command as array for proper argument handling
  local buildx_args=(
    --platform "$PLATFORM"
    --file "$DOCKERFILE"
    --cache-from "type=gha,scope=${cache_scope}"
    --cache-from "type=registry,ref=${CACHE_TAG}-${VARIANT}"
    --cache-to "type=gha,mode=max,scope=${cache_scope}"
    --cache-to "type=registry,ref=${CACHE_TAG}-${VARIANT},mode=max"
    --label "org.opencontainers.image.source=${SOURCE_URL}"
    --label "org.opencontainers.image.revision=${REVISION}"
  )

  # Add VERSION build arg if provided (used by Dockerfiles that clone specific versions)
  if [[ -n "$VERSION" ]]; then
    buildx_args+=(--build-arg "VERSION=${VERSION}")
    echo "Using VERSION build arg: ${VERSION}"
  fi

  # Add final args
  buildx_args+=(
    --metadata-file /tmp/build-metadata.json
    --output "type=image,name=${IMAGE_REPO},push-by-digest=true,name-canonical=true,push=true"
    "$IMAGE_NAME"
  )

  # Execute docker buildx build
  docker buildx build "${buildx_args[@]}"

  echo "Build completed successfully"
  return 0
}

#######################################
# Main execution
#######################################
main() {
  parse_args "$@"
  build_image
  exit 0
}

# Run main function
main "$@"
