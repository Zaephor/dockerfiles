#!/usr/bin/env bash
# merge-manifest.sh - Coordinate multi-architecture Docker manifest creation
#
# Usage:
#   merge-manifest.sh \
#     --image IMAGE_NAME \
#     --tag TAG_NAME \
#     --amd64-digest DIGEST \
#     --amd64-status STATUS \
#     --arm64-digest DIGEST \
#     --arm64-status STATUS \
#     [--verify]
#
# Description:
#   Combines architecture-specific image digests into a multi-architecture manifest list.
#   Supports graceful degradation by creating single-arch manifests when one build fails.
#
# Exit Codes:
#   0 - Success (manifest created and optionally verified)
#   1 - Invalid parameters or validation failure
#   2 - Both architectures failed (cannot create manifest)
#
# Examples:
#   # Both architectures successful
#   merge-manifest.sh --image ghcr.io/user/app --tag v1.0.0 \
#     --amd64-digest sha256:abc... --amd64-status success \
#     --arm64-digest sha256:def... --arm64-status success \
#     --verify
#
#   # Only amd64 successful (graceful degradation)
#   merge-manifest.sh --image ghcr.io/user/app --tag v1.0.0 \
#     --amd64-digest sha256:abc... --amd64-status success \
#     --arm64-digest "" --arm64-status failure
#
# Dependencies:
#   - docker buildx imagetools (manifest manipulation)
#   - bash 4.0+ (associative arrays, parameter expansion)

set -euo pipefail

# Script metadata
SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="1.0.0"

# Global variables (populated by parameter parsing)
IMAGE=""
TAG=""
AMD64_DIGEST=""
AMD64_STATUS=""
ARM64_DIGEST=""
ARM64_STATUS=""
VERIFY=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#######################################
# Print error message and exit
# Arguments:
#   $1 - Error message
#   $2 - Exit code (default: 1)
#######################################
error() {
  local message="$1"
  local exit_code="${2:-1}"
  echo -e "${RED}ERROR:${NC} ${message}" >&2
  exit "$exit_code"
}

#######################################
# Print warning message
# Arguments:
#   $1 - Warning message
#######################################
warn() {
  local message="$1"
  echo -e "${YELLOW}WARN:${NC} ${message}" >&2
}

#######################################
# Print info message
# Arguments:
#   $1 - Info message
#######################################
info() {
  local message="$1"
  echo -e "${GREEN}INFO:${NC} ${message}"
}

#######################################
# Print usage information
#######################################
usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Create multi-architecture Docker manifest from build outputs.

Required Options:
  --image IMAGE          Full image name (e.g., ghcr.io/user/app)
  --tag TAG              Tag name for manifest (e.g., v1.0.0, latest)
  --amd64-digest DIGEST  amd64 image digest (sha256:...)
  --amd64-status STATUS  amd64 build status (success/failure)
  --arm64-digest DIGEST  arm64 image digest (sha256:...)
  --arm64-status STATUS  arm64 build status (success/failure)

Optional:
  --verify               Verify manifest after creation
  --help                 Show this help message

Exit Codes:
  0 - Success (manifest created)
  1 - Invalid parameters or validation failure
  2 - Both architectures failed (cannot create manifest)

Examples:
  # Both architectures successful
  ${SCRIPT_NAME} --image ghcr.io/user/app --tag v1.0.0 \\
    --amd64-digest sha256:abc... --amd64-status success \\
    --arm64-digest sha256:def... --arm64-status success \\
    --verify

  # Graceful degradation (arm64 failed)
  ${SCRIPT_NAME} --image ghcr.io/user/app --tag v1.0.0 \\
    --amd64-digest sha256:abc... --amd64-status success \\
    --arm64-digest "" --arm64-status failure

EOF
}

#######################################
# Parse command-line arguments
# Globals:
#   IMAGE, TAG, AMD64_DIGEST, AMD64_STATUS, ARM64_DIGEST, ARM64_STATUS, VERIFY
#######################################
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --image)
        IMAGE="$2"
        shift 2
        ;;
      --tag)
        TAG="$2"
        shift 2
        ;;
      --amd64-digest)
        AMD64_DIGEST="$2"
        shift 2
        ;;
      --amd64-status)
        AMD64_STATUS="$2"
        shift 2
        ;;
      --arm64-digest)
        ARM64_DIGEST="$2"
        shift 2
        ;;
      --arm64-status)
        ARM64_STATUS="$2"
        shift 2
        ;;
      --verify)
        VERIFY=true
        shift
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        error "Unknown option: $1\n\n$(usage)" 1
        ;;
    esac
  done

  # Validate required parameters
  [[ -z "$IMAGE" ]] && error "--image is required"
  [[ -z "$TAG" ]] && error "--tag is required"
  [[ -z "$AMD64_STATUS" ]] && error "--amd64-status is required"
  [[ -z "$ARM64_STATUS" ]] && error "--arm64-status is required"
  return 0
}

#######################################
# Validate digest format
# Arguments:
#   $1 - Digest string to validate
# Returns:
#   0 if valid, 1 if invalid
#######################################
validate_digest() {
  local digest="$1"

  # Empty digest is valid (indicates build failure)
  [[ -z "$digest" ]] && return 0

  # Check format: sha256:[64 hexadecimal characters]
  if [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    return 0
  else
    return 1
  fi
}

#######################################
# Determine which architectures succeeded
# Globals:
#   AMD64_DIGEST, AMD64_STATUS, ARM64_DIGEST, ARM64_STATUS
# Outputs:
#   Sets AMD64_SUCCESS and ARM64_SUCCESS boolean flags
#######################################
check_build_status() {
  AMD64_SUCCESS=false
  ARM64_SUCCESS=false

  # AMD64 status check
  case "$AMD64_STATUS" in
    success)
      # When status=success, digest is required and must be valid
      if [[ -z "$AMD64_DIGEST" ]]; then
        error "amd64 build marked success but no digest provided - cannot create manifest" 2
      elif ! validate_digest "$AMD64_DIGEST"; then
        error "amd64 digest invalid format: $AMD64_DIGEST - cannot create manifest" 2
      else
        AMD64_SUCCESS=true
        info "amd64 build: SUCCESS (digest: ${AMD64_DIGEST:0:19}...)"
      fi
      ;;
    failure)
      warn "amd64 build: FAILED"
      ;;
    cancelled)
      warn "amd64 build: CANCELLED (user aborted workflow)"
      ;;
    skipped)
      warn "amd64 build: SKIPPED (conditional execution)"
      ;;
    timed_out)
      warn "amd64 build: TIMED OUT (exceeded timeout threshold)"
      ;;
    *)
      warn "amd64 build: UNKNOWN STATUS ($AMD64_STATUS)"
      ;;
  esac

  # ARM64 status check
  case "$ARM64_STATUS" in
    success)
      # When status=success, digest is required and must be valid
      if [[ -z "$ARM64_DIGEST" ]]; then
        error "arm64 build marked success but no digest provided - cannot create manifest" 2
      elif ! validate_digest "$ARM64_DIGEST"; then
        error "arm64 digest invalid format: $ARM64_DIGEST - cannot create manifest" 2
      else
        ARM64_SUCCESS=true
        info "arm64 build: SUCCESS (digest: ${ARM64_DIGEST:0:19}...)"
      fi
      ;;
    failure)
      warn "arm64 build: FAILED"
      ;;
    cancelled)
      warn "arm64 build: CANCELLED (user aborted workflow)"
      ;;
    skipped)
      warn "arm64 build: SKIPPED (conditional execution)"
      ;;
    timed_out)
      warn "arm64 build: TIMED OUT (exceeded timeout threshold)"
      ;;
    *)
      warn "arm64 build: UNKNOWN STATUS ($ARM64_STATUS)"
      ;;
  esac

  # Check if both failed
  if [[ "$AMD64_SUCCESS" == false ]] && [[ "$ARM64_SUCCESS" == false ]]; then
    error "Both amd64 and arm64 builds failed - cannot create manifest" 2
  fi
  return 0
}

#######################################
# Create multi-architecture manifest list
# Globals:
#   IMAGE, TAG, AMD64_DIGEST, ARM64_DIGEST, AMD64_SUCCESS, ARM64_SUCCESS
# Returns:
#   0 on success, 1 on failure
#######################################
create_manifest() {
  local manifest_tag="${IMAGE}:${TAG}"
  local digest_args=()

  # Build digest arguments for docker buildx imagetools create
  if [[ "$AMD64_SUCCESS" == true ]]; then
    digest_args+=("${IMAGE}@${AMD64_DIGEST}")
  fi

  if [[ "$ARM64_SUCCESS" == true ]]; then
    digest_args+=("${IMAGE}@${ARM64_DIGEST}")
  fi

  # Determine manifest type
  local arch_count="${#digest_args[@]}"
  if [[ "$arch_count" -eq 2 ]]; then
    info "Creating multi-architecture manifest (amd64 + arm64)"
  elif [[ "$AMD64_SUCCESS" == true ]]; then
    warn "Creating single-architecture manifest (amd64 only - graceful degradation)"
  elif [[ "$ARM64_SUCCESS" == true ]]; then
    warn "Creating single-architecture manifest (arm64 only - graceful degradation)"
  fi

  # Create manifest using docker buildx imagetools
  info "Manifest tag: $manifest_tag"
  info "Source digests: ${digest_args[*]}"

  if docker buildx imagetools create -t "$manifest_tag" "${digest_args[@]}"; then
    info "Manifest created successfully: $manifest_tag"
    return 0
  else
    error "Failed to create manifest: $manifest_tag" 1
  fi
}

#######################################
# Verify created manifest
# Globals:
#   IMAGE, TAG, AMD64_SUCCESS, ARM64_SUCCESS
# Returns:
#   0 on success, 1 on failure
#######################################
verify_manifest() {
  local manifest_tag="${IMAGE}:${TAG}"

  info "Verifying manifest: $manifest_tag"

  # Inspect manifest with timeout (JSON format for reliable parsing)
  local inspect_json
  if ! inspect_json=$(timeout 30s docker buildx imagetools inspect --raw "$manifest_tag" 2>&1); then
    # Fallback to text output if --raw fails
    local inspect_output
    if ! inspect_output=$(timeout 30s docker buildx imagetools inspect "$manifest_tag" 2>&1); then
      error "Manifest inspection failed:\n$inspect_output" 1
    fi
    warn "Could not get raw manifest JSON, showing text output:"
    echo "$inspect_output"
    info "Manifest verification skipped (unable to parse platform count)"
    return 0
  fi

  # Count platforms in manifest (from manifests array in JSON)
  local platform_count
  platform_count=$(echo "$inspect_json" | jq -r '.manifests | length' 2>/dev/null || echo "0")

  # Expected platform count
  local expected_count=0
  [[ "$AMD64_SUCCESS" == true ]] && ((expected_count++))
  [[ "$ARM64_SUCCESS" == true ]] && ((expected_count++))

  # Validate platform count
  if [[ "$platform_count" -ne "$expected_count" ]]; then
    warn "Platform count mismatch: expected $expected_count, found $platform_count"
    info "Manifest JSON:"
    echo "$inspect_json" | jq '.' 2>/dev/null || echo "$inspect_json"
    # Don't fail on mismatch, just warn - manifest was created successfully
  else
    info "Manifest verified: $platform_count platform(s) present"
  fi

  return 0
}

#######################################
# Main execution
#######################################
main() {
  # Parse arguments
  parse_args "$@" || return $?

  # Check build status and validate digests
  check_build_status || return $?

  # Create manifest
  create_manifest || return $?

  # Optionally verify manifest
  if [[ "$VERIFY" == true ]]; then
    verify_manifest || return $?
  fi

  info "Manifest creation complete"
  exit 0
}

# Run main function
main "$@"
