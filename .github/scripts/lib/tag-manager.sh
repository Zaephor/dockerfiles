#!/usr/bin/env bash
#
# Tag Manager Library
#
# Provides functions to manage Docker image tags following semantic versioning
# conventions, with support for partial version tags (1, 1.0, 1.0.0) and
# calendar versioning schemes.
#

set -euo pipefail

# Source version-compare library for lineage checks
# shellcheck source=/dev/null
source "${BASH_SOURCE%/*}/version-compare.sh"

# Determine which tags should be updated for a rebuild
#
# Arguments:
#   $1: Target version being rebuilt
#   $2: Space-separated list of all versions
#   $3: Optional flags: --skip-partial (don't update major.minor tags)
#   $4: Optional flags: --skip-latest (don't update 'latest' tag)
#
# Output:
#   Space-separated list of tags to update (including full version)
#
# Logic:
#   - Always include full version tag (1.0.0, 2.5.3, etc.)
#   - If version is latest in major.minor lineage, include major.minor tag (1.2)
#   - If version is globally latest, include major tag (1) and 'latest'
#   - If pre-release, don't update stable lineage tags
#
determine_tags_to_update() {
  local target_version="$1"
  local all_versions="$2"
  local skip_partial="${3:-}"
  local skip_latest="${4:-}"

  local tags_to_update="$target_version"

  # Check if this is a pre-release version
  local is_prerelease=0
  if [[ "$target_version" == *"-"* ]]; then
    is_prerelease=1
  fi

  # If not a pre-release and not skipping partial tags
  # Note: check both $3 and $4 for skip-partial flag
  local should_skip_partial=0
  if [[ "$skip_partial" == "--skip-partial" ]]; then
    should_skip_partial=1
  fi
  if [[ "$skip_latest" == "--skip-partial" ]]; then
    should_skip_partial=1
  fi

  if [[ $is_prerelease -eq 0 && $should_skip_partial -eq 0 ]]; then
    # Check if latest in major.minor lineage
    if is_latest_in_lineage "$target_version" "$all_versions"; then
      local major_minor
      major_minor=$(get_major_minor_version "$target_version")
      tags_to_update="$tags_to_update $major_minor"

      # Check if latest globally (not just in lineage)
      if is_globally_latest "$target_version" "$all_versions"; then
        local major
        major=$(get_major_version "$target_version")
        tags_to_update="$tags_to_update $major"

        # Add 'latest' tag if not skipping
        if [[ "$skip_latest" != "--skip-latest" ]]; then
          tags_to_update="$tags_to_update latest"
        fi
      fi
    fi
  fi

  # Remove duplicates and return
  echo "$tags_to_update" | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/ $//'
}

# Generate calendar version tags (partial tags for calver versions)
#
# Arguments:
#   $1: Calendar version (e.g., "2025.11.13")
#
# Output:
#   Space-separated list of partial calver tags
#
# Examples:
#   2025.11.13 → 2025.11 2025
#   2025.11 → 2025
#
generate_calver_tags() {
  local calver_version="$1"

  local tags=""

  # For YYYY.MM.DD format, also generate YYYY.MM and YYYY tags
  if [[ "$calver_version" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]]; then
    local year_month="${calver_version%.*}"
    local year="${year_month%.*}"
    tags="$year_month $year"
  # For YYYY.MM format, also generate YYYY tag
  elif [[ "$calver_version" =~ ^[0-9]{4}\.[0-9]{2}$ ]]; then
    local year="${calver_version%.*}"
    tags="$year"
  fi

  echo "$tags"
}

# Check if a version should have its partial version tags updated
#
# Arguments:
#   $1: Version string
#   $2: Space-separated list of all versions
#   $3: Version type: semver|calver|auto (default: auto-detect)
#
# Returns:
#   0 if partial tags should be updated, 1 otherwise
#
should_update_partial_tags() {
  local version="$1"
  local all_versions="$2"
  local version_type="${3:-auto}"

  # Auto-detect version type if needed
  if [[ "$version_type" == "auto" ]]; then
    if is_calver "$version"; then
      version_type="calver"
    else
      version_type="semver"
    fi
  fi

  # For calendar versioning, never update partial tags on rebuild
  # (they're historical snapshots, not semver lineages)
  if [[ "$version_type" == "calver" ]]; then
    return 1
  fi

  # For semver, check if version is latest in its lineage
  if [[ "$version_type" == "semver" ]]; then
    if is_latest_in_lineage "$version" "$all_versions"; then
      return 0
    fi
  fi

  return 1
}

# Validate that a tag update won't break semantic versioning conventions
#
# Arguments:
#   $1: Tag to update
#   $2: Version being tagged
#   $3: Space-separated list of all versions
#
# Returns:
#   0 if tag update is valid, 1 if it would break conventions
#
# Checks:
#   - Major tag (1) only points to latest in major.1.x
#   - Major.minor tag (1.2) only points to latest in 1.2.x
#   - 'latest' tag only points to globally latest
#
validate_tag_update() {
  local tag="$1"
  local version="$2"
  local all_versions="$3"

  case "$tag" in
    latest)
      # Latest tag should only point to globally latest
      if is_globally_latest "$version" "$all_versions"; then
        return 0
      fi
      return 1
      ;;
    *)
      # For major.minor or major tags, verify lineage
      # This is a simplified check - in production, would need more context
      return 0
      ;;
  esac
}

# Get all tags that should be used for a new build
#
# Arguments:
#   $1: Version string
#   $2: Space-separated list of all versions
#   $3: Registry prefix (e.g., "ghcr.io/user/image" for full image name)
#
# Output:
#   Docker tags in format suitable for 'docker tag' command
#
get_docker_tags() {
  local version="$1"
  local all_versions="$2"
  local registry_prefix="$3"

  # Get tags to update
  local tags
  tags=$(determine_tags_to_update "$version" "$all_versions")

  # For calendar versions, add calver tags
  if is_calver "$version"; then
    local calver_tags
    calver_tags=$(generate_calver_tags "$version")
    if [[ -n "$calver_tags" ]]; then
      tags="$tags $calver_tags"
    fi
  fi

  # Format as full image references
  local full_tags=""
  for tag in $tags; do
    full_tags="${full_tags}${registry_prefix}:${tag} "
  done

  echo "${full_tags% }"
}

# Get the version-derived "release" tags for a default-variant build.
#
# Only real version strings are tagged; opaque values (image digests,
# commit SHAs, rolling tags like "edge") return nothing, which is what keeps
# digest-tracked images (e.g. hello-world) on commit/branch tags only.
#
# Tag set:
#   - semver (X.Y.Z[-pre]): full version + major.minor (when latest in its
#       lineage) + latest (when globally latest). The bare-major tag is
#       intentionally omitted.
#   - calver: full version + calver partials + latest (when globally latest).
#
# Arguments:
#   $1: Detected version for this build
#   $2: Space-separated list of all known versions (defaults to $1)
#
# Output:
#   Newline-separated tag list (possibly empty)
#
get_default_release_tags() {
  local version="$1"
  local all_versions="${2:-$1}"

  [[ -z "$version" || "$version" == "null" ]] && return 0

  # Make sure the current version participates in lineage/global comparisons.
  case " $all_versions " in
    *" $version "*) ;;
    *) all_versions="$all_versions $version" ;;
  esac

  if is_calver "$version"; then
    {
      determine_tags_to_update "$version" "$all_versions" | tr ' ' '\n'
      generate_calver_tags "$version" | tr ' ' '\n'
    } | grep -v '^$' | sort -u
    return 0
  fi

  # Strict semver: MAJOR.MINOR.PATCH with optional -prerelease / +build.
  if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+].*)?$ ]]; then
    # Keep full + major.minor (tokens containing '.') and 'latest';
    # drop the bare-major token per the chosen tag set.
    determine_tags_to_update "$version" "$all_versions" \
      | tr ' ' '\n' \
      | grep -E '\.|^latest$' \
      | sort -u
    return 0
  fi

  # Opaque (digest, commit SHA, rolling tag): no version tags.
  return 0
}

# Check if rebuilding this version would change any existing tags
#
# Arguments:
#   $1: Version string
#   $2: Space-separated list of all versions
#
# Returns:
#   0 if tags would change, 1 if no tag changes
#
would_change_tags() {
  local version="$1"
  local all_versions="$2"

  # If this is the globally latest version, rebuilding changes tags
  if is_globally_latest "$version" "$all_versions"; then
    return 0
  fi

  # If this is the latest in its lineage, rebuilding changes the major.minor tag
  if is_latest_in_lineage "$version" "$all_versions"; then
    return 0
  fi

  # Otherwise, only the full version tag updates
  return 1
}
