#!/usr/bin/env bash
#
# Version Parser Library
#
# Provides functions to parse and normalize diverse version formats:
# - Semantic versions (1.2.3, v1.2.3, 1.2.3-rc1)
# - Calendar versions (2024.11.13, 2024.11, 24.11.13)
# - Date versions (20241113, 2024-11-13)
# - Opaque versions (commit SHAs, rolling, edge)
#
# All versions are normalized with format prefix: "semver:", "calver:", "date:", "opaque:"
#

set -euo pipefail

# Strip common version prefixes (v, version-, etc.)
#
# Arguments:
#   $1: Version string
#
# Output:
#   Normalized version string (without prefix)
#
normalize_prefix() {
  local version="$1"

  # Strip leading prefixes (order matters: longer prefixes first)
  version="${version#version-}"
  version="${version#release-}"
  version="${version#v}"

  echo "$version"
}

# Parse version format and return format-prefixed version
#
# Arguments:
#   $1: Version string (raw input)
#
# Output:
#   Format-prefixed version (e.g., "semver:1.2.3", "calver:2024.11.13")
#
# Format detection order:
#   1. Semantic version: X.Y.Z or X.Y.Z-prerelease
#   2. Calendar version: YYYY.MM.DD, YYYY.MM, YY.MM.DD
#   3. Date version: YYYYMMDD, YYYY-MM-DD
#   4. Opaque: Everything else (commit SHAs, arbitrary strings)
#
parse_version() {
  local version="$1"

  # Normalize prefix
  version=$(normalize_prefix "$version")

  # Calver YYYY.MM.DD (e.g., 2024.11.13) - check BEFORE semver
  if [[ "$version" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]]; then
    echo "calver:$version"
    return 0
  fi

  # Calver YYYY.MM (e.g., 2024.11)
  if [[ "$version" =~ ^[0-9]{4}\.[0-9]{2}$ ]]; then
    echo "calver:$version"
    return 0
  fi

  # Calver YY.MM.DD (e.g., 24.11.13)
  if [[ "$version" =~ ^[0-9]{2}\.[0-9]{2}\.[0-9]{2}$ ]]; then
    echo "calver:$version"
    return 0
  fi

  # Semver: X.Y.Z or X.Y.Z-prerelease
  # Examples: 1.2.3, 1.2.3-rc1, 1.2.3-alpha.1
  if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-\+].+)?$ ]]; then
    echo "semver:$version"
    return 0
  fi

  # Date YYYYMMDD (e.g., 20241113)
  if [[ "$version" =~ ^[0-9]{8}$ ]]; then
    echo "date:$version"
    return 0
  fi

  # Date YYYY-MM-DD (e.g., 2024-11-13)
  if [[ "$version" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "date:$version"
    return 0
  fi

  # Opaque: commit SHA, rolling, edge, nightly, etc.
  echo "opaque:$version"
  return 0
}

# Extract the format from a parsed version
#
# Arguments:
#   $1: Parsed version string (format-prefixed, e.g., "semver:1.2.3")
#
# Output:
#   Format name: "semver", "calver", "date", or "opaque"
#
get_format() {
  local parsed_version="$1"
  echo "${parsed_version%%:*}"
}

# Extract the version value from a parsed version
#
# Arguments:
#   $1: Parsed version string (format-prefixed, e.g., "semver:1.2.3")
#
# Output:
#   Version value: "1.2.3"
#
get_version_value() {
  local parsed_version="$1"
  echo "${parsed_version#*:}"
}

# Compare two semantic versions
#
# Arguments:
#   $1: First semver (X.Y.Z format)
#   $2: Second semver (X.Y.Z format)
#
# Output:
#   1 if first > second
#   0 if equal
#   -1 if first < second
#
# Returns:
#   0 on success, 1 on invalid format
#
compare_semver() {
  local v1="$1"
  local v2="$2"

  # Extract base version (without pre-release suffix)
  local base1="${v1%%-*}"
  local base2="${v2%%-*}"

  # Split into major.minor.patch
  local IFS='.'
  read -ra parts1 <<< "$base1"
  read -ra parts2 <<< "$base2"

  # Compare major version
  if [[ ${parts1[0]:-0} -gt ${parts2[0]:-0} ]]; then
    echo 1
    return 0
  elif [[ ${parts1[0]:-0} -lt ${parts2[0]:-0} ]]; then
    echo -1
    return 0
  fi

  # Compare minor version
  if [[ ${parts1[1]:-0} -gt ${parts2[1]:-0} ]]; then
    echo 1
    return 0
  elif [[ ${parts1[1]:-0} -lt ${parts2[1]:-0} ]]; then
    echo -1
    return 0
  fi

  # Compare patch version
  if [[ ${parts1[2]:-0} -gt ${parts2[2]:-0} ]]; then
    echo 1
    return 0
  elif [[ ${parts1[2]:-0} -lt ${parts2[2]:-0} ]]; then
    echo -1
    return 0
  fi

  # Check pre-release versions
  local pre1="${v1#*-}"
  local pre2="${v2#*-}"

  if [[ "$v1" != "$pre1" && "$v2" == "$pre2" ]]; then
    # v1 has pre-release, v2 doesn't (v2 > v1)
    echo -1
    return 0
  elif [[ "$v1" == "$pre1" && "$v2" != "$pre2" ]]; then
    # v2 has pre-release, v1 doesn't (v1 > v2)
    echo 1
    return 0
  elif [[ "$v1" != "$pre1" && "$v2" != "$pre2" ]]; then
    # Both have pre-release, compare lexicographically
    if [[ "$pre1" > "$pre2" ]]; then
      echo 1
    elif [[ "$pre1" < "$pre2" ]]; then
      echo -1
    else
      echo 0
    fi
    return 0
  fi

  # Versions are equal
  echo 0
  return 0
}

# Convert calver version to ISO date format for comparison
#
# Arguments:
#   $1: Calver version (YYYY.MM.DD, YYYY.MM, or YY.MM.DD)
#
# Output:
#   ISO date string (YYYY-MM-DD)
#
# Returns:
#   0 on success, 1 on invalid format
#
calver_to_iso_date() {
  local calver="$1"

  if [[ "$calver" =~ ^([0-9]{4})\.([0-9]{2})\.([0-9]{2})$ ]]; then
    # YYYY.MM.DD format
    echo "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
    return 0
  elif [[ "$calver" =~ ^([0-9]{4})\.([0-9]{2})$ ]]; then
    # YYYY.MM format (use 01 for day)
    echo "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-01"
    return 0
  elif [[ "$calver" =~ ^([0-9]{2})\.([0-9]{2})\.([0-9]{2})$ ]]; then
    # YY.MM.DD format (assume 20YY)
    echo "20${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
    return 0
  else
    return 1
  fi
}

# Convert date version to ISO date format for comparison
#
# Arguments:
#   $1: Date version (YYYYMMDD or YYYY-MM-DD)
#
# Output:
#   ISO date string (YYYY-MM-DD)
#
# Returns:
#   0 on success, 1 on invalid format
#
date_to_iso_format() {
  local date="$1"

  if [[ "$date" =~ ^([0-9]{8})$ ]]; then
    # YYYYMMDD format
    local year="${date:0:4}"
    local month="${date:4:2}"
    local day="${date:6:2}"
    echo "$year-$month-$day"
    return 0
  elif [[ "$date" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]]; then
    # Already ISO format
    echo "$date"
    return 0
  else
    return 1
  fi
}

# Compare two parsed versions
#
# Arguments:
#   $1: First parsed version (format-prefixed, e.g., "semver:1.2.3")
#   $2: Second parsed version (format-prefixed, e.g., "semver:1.2.4")
#
# Output:
#   1 if first > second
#   0 if equal
#   -1 if first < second
#
# Returns:
#   0 on success, 1 on format mismatch or invalid format
#
compare_versions() {
  local parsed_v1="$1"
  local parsed_v2="$2"

  local format1=$(get_format "$parsed_v1")
  local format2=$(get_format "$parsed_v2")

  local v1=$(get_version_value "$parsed_v1")
  local v2=$(get_version_value "$parsed_v2")

  # Formats must match for comparison
  if [[ "$format1" != "$format2" ]]; then
    echo "ERROR: Cannot compare different formats ($format1 vs $format2)" >&2
    return 1
  fi

  case "$format1" in
    semver)
      compare_semver "$v1" "$v2"
      return $?
      ;;
    calver)
      local iso1=$(calver_to_iso_date "$v1") || return 1
      local iso2=$(calver_to_iso_date "$v2") || return 1
      if [[ "$iso1" > "$iso2" ]]; then
        echo 1
      elif [[ "$iso1" < "$iso2" ]]; then
        echo -1
      else
        echo 0
      fi
      return 0
      ;;
    date)
      local iso1=$(date_to_iso_format "$v1") || return 1
      local iso2=$(date_to_iso_format "$v2") || return 1
      if [[ "$iso1" > "$iso2" ]]; then
        echo 1
      elif [[ "$iso1" < "$iso2" ]]; then
        echo -1
      else
        echo 0
      fi
      return 0
      ;;
    opaque)
      # Opaque versions cannot be compared
      echo "ERROR: Opaque versions cannot be compared ($v1 vs $v2)" >&2
      return 1
      ;;
    *)
      echo "ERROR: Unknown format: $format1" >&2
      return 1
      ;;
  esac
}

# Determine if a version is "newer" than another
#
# Arguments:
#   $1: First parsed version (format-prefixed)
#   $2: Second parsed version (format-prefixed)
#
# Returns:
#   0 if first >= second (newer or equal)
#   1 if first < second (older)
#
is_newer_or_equal() {
  local result
  result=$(compare_versions "$1" "$2") || return 1
  [[ "$result" -ge 0 ]]
}

# Find the maximum (newest) version from a list of parsed versions
#
# Arguments:
#   One or more parsed versions (format-prefixed)
#
# Output:
#   The newest version (format-prefixed)
#
# Returns:
#   0 on success, 1 if list is empty or has format mismatch
#
find_max_version() {
  local versions=("$@")

  if [[ ${#versions[@]} -eq 0 ]]; then
    echo "ERROR: No versions provided" >&2
    return 1
  fi

  local max="${versions[0]}"

  for version in "${versions[@]:1}"; do
    local result
    result=$(compare_versions "$version" "$max") || return 1
    if [[ "$result" -gt 0 ]]; then
      max="$version"
    fi
  done

  echo "$max"
  return 0
}

# Sort versions in ascending order
#
# Arguments:
#   One or more parsed versions (format-prefixed)
#
# Output:
#   Sorted versions (one per line), oldest first
#
# Returns:
#   0 on success, 1 on format mismatch or empty list
#
sort_versions() {
  local versions=("$@")

  if [[ ${#versions[@]} -eq 0 ]]; then
    echo "ERROR: No versions provided" >&2
    return 1
  fi

  # Simple bubble sort (acceptable for small version lists)
  local n=${#versions[@]}
  local i j

  for ((i = 0; i < n; i++)); do
    for ((j = 0; j < n - i - 1; j++)); do
      local result
      result=$(compare_versions "${versions[$((j+1))]}" "${versions[$j]}") || return 1
      if [[ "$result" -lt 0 ]]; then
        # Swap
        local tmp="${versions[$j]}"
        versions[$j]="${versions[$((j+1))]}"
        versions[$((j+1))]="$tmp"
      fi
    done
  done

  # Output sorted versions
  for version in "${versions[@]}"; do
    echo "$version"
  done

  return 0
}
