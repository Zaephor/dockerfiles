#!/usr/bin/env bash
#
# Version Comparison Library
#
# Provides functions to compare versions semantically, detect calendar versioning,
# and determine version lineage relationships for rewind/rebuild scenarios.
#

set -euo pipefail

# Compare two semantic versions and return ordering
#
# Arguments:
#   $1: Version 1 (e.g., "1.2.3" or "1.2.3-beta.1")
#   $2: Version 2 (e.g., "1.2.4")
#
# Returns:
#   0 if version1 < version2
#   1 if version1 = version2
#   2 if version1 > version2
#
# Uses GNU sort with version comparison (sort -V)
# Note: sort -V may not handle prerelease suffixes correctly, but for most cases it works
#
compare_versions() {
  local v1="$1"
  local v2="$2"

  # If versions are equal, return 1
  if [[ "$v1" == "$v2" ]]; then
    return 1
  fi

  # Use sort -V for semantic versioning
  # Create a temporary file to avoid issues with newlines
  local sorted
  sorted=$(printf '%s\n' "$v1" "$v2" | sort -V)
  local first_line
  first_line=$(echo "$sorted" | head -n1)

  # If v1 sorts before v2, return 0
  if [[ "$first_line" == "$v1" ]]; then
    return 0
  fi

  # Otherwise v1 > v2, return 2
  return 2
}

# Detect if a version string uses calendar versioning (YYYY.MM.DD or similar)
#
# Arguments:
#   $1: Version string
#
# Returns:
#   0 if version is calendar versioning, 1 otherwise
#
is_calver() {
  local version="$1"

  # Calendar versioning patterns:
  # YYYY.MM.DD (2025.11.13)
  # YYYY.MM (2025.11)
  # YY.MM.DD (25.11.13)
  if [[ "$version" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]] || \
     [[ "$version" =~ ^[0-9]{4}\.[0-9]{2}$ ]] || \
     [[ "$version" =~ ^[0-9]{2}\.[0-9]{2}\.[0-9]{2}$ ]]; then
    return 0
  fi

  return 1
}

# Extract major version from semantic version string
#
# Arguments:
#   $1: Version string (e.g., "1.2.3" or "1.2.3-beta.1")
#
# Output:
#   Major version number
#
get_major_version() {
  local version="$1"
  # Remove any prerelease suffix and extract first component
  version="${version%-*}"  # Remove prerelease suffix
  echo "${version%%.*}"     # Extract first component
}

# Extract major.minor version from semantic version string
#
# Arguments:
#   $1: Version string (e.g., "1.2.3" or "1.2.3-beta.1")
#
# Output:
#   Major.minor version (e.g., "1.2")
#
get_major_minor_version() {
  local version="$1"
  # Remove any prerelease suffix
  version="${version%-*}"
  # Extract major and minor
  local major="${version%%.*}"
  local rest="${version#*.}"
  local minor="${rest%%.*}"
  echo "${major}.${minor}"
}

# Check if a version is the latest in its lineage (major.minor prefix)
#
# Arguments:
#   $1: Target version
#   $2: Space-separated list of all versions to check against
#
# Returns:
#   0 if target is latest in its major.minor lineage, 1 otherwise
#
is_latest_in_lineage() {
  local target="$1"
  local versions="$2"

  local target_lineage
  target_lineage=$(get_major_minor_version "$target")

  local latest="$target"

  # Iterate through all versions and find the latest in same lineage
  for version in $versions; do
    local lineage
    lineage=$(get_major_minor_version "$version")

    # Only compare versions in same lineage
    if [[ "$lineage" == "$target_lineage" ]]; then
      # Compare using sort -V to find highest
      if [[ "$(printf '%s\n' "$latest" "$version" | sort -V | tail -n1)" == "$version" ]]; then
        latest="$version"
      fi
    fi
  done

  # Return 0 if target is latest in lineage, 1 otherwise
  if [[ "$target" == "$latest" ]]; then
    return 0
  fi

  return 1
}

# Find the latest version in a specific lineage (major.minor prefix)
#
# Arguments:
#   $1: Major.minor prefix (e.g., "1.0")
#   $2: Space-separated list of all versions
#
# Output:
#   Latest version matching the prefix
#
find_latest_in_lineage() {
  local prefix="$1"
  local versions="$2"

  local latest=""

  for version in $versions; do
    local lineage
    lineage=$(get_major_minor_version "$version")

    if [[ "$lineage" == "$prefix" ]]; then
      if [[ -z "$latest" ]] || [[ "$(printf '%s\n' "$latest" "$version" | sort -V | tail -n1)" == "$version" ]]; then
        latest="$version"
      fi
    fi
  done

  echo "$latest"
}

# Check if a version is globally the latest (no higher version exists)
#
# Arguments:
#   $1: Target version
#   $2: Space-separated list of all versions
#
# Returns:
#   0 if target is globally latest, 1 otherwise
#
is_globally_latest() {
  local target="$1"
  local versions="$2"

  # Find the maximum version using sort -V
  local max_version
  max_version=$(printf '%s\n' $versions | sort -V | tail -n1)

  if [[ "$target" == "$max_version" ]]; then
    return 0
  fi

  return 1
}

# Extract calver prefix (YYYY or YYYY.MM) from a calendar version
#
# Arguments:
#   $1: Calendar version (e.g., "2025.11.13")
#
# Output:
#   Calver prefix (e.g., "2025" or "2025.11")
#
get_calver_prefix() {
  local version="$1"

  # For YYYY.MM.DD format, return YYYY and YYYY.MM
  if [[ "$version" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]]; then
    # Extract year and month components
    local year="${version%.*.*}"
    local month="${version%.*}"
    month="${month#*.}"
    echo "$year"
    echo "${year}.${month}"
    return 0
  fi

  # For YYYY.MM format, return YYYY
  if [[ "$version" =~ ^[0-9]{4}\.[0-9]{2}$ ]]; then
    local year="${version%.*}"
    echo "$year"
    return 0
  fi

  return 1
}

# Check if a version is the latest in its lineage (major.minor prefix)
# with support for semver pre-release filtering
#
# Arguments:
#   $1: Target version
#   $2: Space-separated list of all versions to check against
#   $3: Optional filter: --exclude-prerelease (exclude pre-release versions)
#
# Returns:
#   0 if target is latest in its major.minor lineage, 1 otherwise
#
is_latest_in_lineage_advanced() {
  local target="$1"
  local versions="$2"
  local filter="${3:-}"

  local target_lineage
  target_lineage=$(get_major_minor_version "$target")

  local latest="$target"

  # Iterate through all versions and find the latest in same lineage
  for version in $versions; do
    local lineage
    lineage=$(get_major_minor_version "$version")

    # Skip pre-releases if requested
    if [[ "$filter" == "--exclude-prerelease" ]]; then
      if [[ "$version" == *"-"* ]]; then
        continue
      fi
    fi

    # Only compare versions in same lineage
    if [[ "$lineage" == "$target_lineage" ]]; then
      # Compare using sort -V to find highest
      if [[ "$(printf '%s\n' "$latest" "$version" | sort -V | tail -n1)" == "$version" ]]; then
        latest="$version"
      fi
    fi
  done

  # Return 0 if target is latest in lineage, 1 otherwise
  if [[ "$target" == "$latest" ]]; then
    return 0
  fi

  return 1
}

# Find the latest stable version (non-prerelease) in the entire version list
#
# Arguments:
#   $1: Space-separated list of versions
#
# Output:
#   Latest stable version
#
get_latest_stable_version() {
  local versions="$1"

  # Filter out pre-release versions and find max
  printf '%s\n' $versions | grep -v -- '-' | sort -V | tail -n1
}

# Get all versions in a specific major version family (e.g., "1.x.x")
#
# Arguments:
#   $1: Major version number
#   $2: Space-separated list of all versions
#
# Output:
#   Space-separated list of versions matching major.x.x
#
get_versions_for_major() {
  local major="$1"
  local versions="$2"

  local matching_versions=""

  for version in $versions; do
    local version_major
    version_major=$(get_major_version "$version")

    if [[ "$version_major" == "$major" ]]; then
      matching_versions="${matching_versions} $version"
    fi
  done

  echo "$matching_versions" | xargs
}
