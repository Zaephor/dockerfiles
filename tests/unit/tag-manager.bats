#!/usr/bin/env bats
#
# Tests for tag-manager.sh library
#

# Load the library to test
load ../../.github/scripts/lib/tag-manager.sh

@test "determine_tags_to_update: old version only gets full version tag" {
  local versions="1.0.0 1.0.1 1.0.2 1.1.0 2.0.0"
  run determine_tags_to_update "1.0.0" "$versions"
  [ "$status" -eq 0 ]
  # Should only contain the version itself, no major/minor tags
  [ "$output" = "1.0.0" ]
}

@test "determine_tags_to_update: latest in lineage gets major.minor tag" {
  local versions="1.0.0 1.0.1 1.0.2 1.1.0 2.0.0"
  run determine_tags_to_update "1.0.2" "$versions"
  [ "$status" -eq 0 ]
  # Should include version and major.minor
  [[ "$output" == *"1.0.2"* ]]
  [[ "$output" == *"1.0"* ]]
}

@test "determine_tags_to_update: globally latest gets all tags" {
  local versions="1.0.0 1.0.1 1.0.2 1.1.0 2.0.0"
  run determine_tags_to_update "2.0.0" "$versions"
  [ "$status" -eq 0 ]
  # Should include version, major.minor, major, and latest
  [[ "$output" == *"2.0.0"* ]]
  [[ "$output" == *"2.0"* ]]
  [[ "$output" == *"2"* ]]
  [[ "$output" == *"latest"* ]]
}

@test "determine_tags_to_update: pre-release doesn't get stable tags" {
  local versions="1.0.0 1.0.1 2.0.0-rc.1 2.0.0"
  run determine_tags_to_update "2.0.0-rc.1" "$versions"
  [ "$status" -eq 0 ]
  # Pre-release should only get the full tag
  [ "$output" = "2.0.0-rc.1" ]
}

@test "determine_tags_to_update: respects --skip-partial flag" {
  local versions="1.0.0 1.0.1 1.0.2 2.0.0"
  run determine_tags_to_update "2.0.0" "$versions" "--skip-partial"
  [ "$status" -eq 0 ]
  # Should not include major.minor or major tags
  [[ "$output" == *"2.0.0"* ]]
  [[ "$output" != *" 2.0 "* ]]
  [[ "$output" != *" 2 "* ]]
}

@test "determine_tags_to_update: respects --skip-latest flag" {
  local versions="1.0.0 1.0.1 1.0.2 2.0.0"
  run determine_tags_to_update "2.0.0" "$versions" "" "--skip-latest"
  [ "$status" -eq 0 ]
  # Should not include 'latest' tag
  [[ "$output" == *"2.0.0"* ]]
  [[ "$output" != *"latest"* ]]
}

@test "generate_calver_tags: generates YYYY.MM and YYYY for YYYY.MM.DD" {
  run generate_calver_tags "2025.11.13"
  [ "$status" -eq 0 ]
  # Should generate both year.month and year
  [[ "$output" == *"2025.11"* ]]
  [[ "$output" == *"2025"* ]]
}

@test "generate_calver_tags: generates YYYY for YYYY.MM" {
  run generate_calver_tags "2025.11"
  [ "$status" -eq 0 ]
  [ "$output" = "2025" ]
}

@test "should_update_partial_tags: returns 1 for calver" {
  local versions="2025.01.01 2025.01.15 2025.02.03"
  run should_update_partial_tags "2025.02.03" "$versions" "calver"
  [ "$status" -eq 1 ]
}

@test "should_update_partial_tags: returns 0 for latest in semver lineage" {
  local versions="1.0.0 1.0.1 1.0.2 1.1.0"
  run should_update_partial_tags "1.0.2" "$versions" "semver"
  [ "$status" -eq 0 ]
}

@test "should_update_partial_tags: returns 1 for old semver" {
  local versions="1.0.0 1.0.1 1.0.2 1.1.0"
  run should_update_partial_tags "1.0.0" "$versions" "semver"
  [ "$status" -eq 1 ]
}

@test "should_update_partial_tags: auto-detects calver" {
  local versions="2025.01.01 2025.01.15 2025.02.03"
  run should_update_partial_tags "2025.02.03" "$versions" "auto"
  [ "$status" -eq 1 ]
}

@test "validate_tag_update: latest tag valid for globally latest" {
  local versions="1.0.0 1.0.1 2.0.0"
  run validate_tag_update "latest" "2.0.0" "$versions"
  [ "$status" -eq 0 ]
}

@test "validate_tag_update: latest tag invalid for old version" {
  local versions="1.0.0 1.0.1 2.0.0"
  run validate_tag_update "latest" "1.0.1" "$versions"
  [ "$status" -eq 1 ]
}

@test "get_docker_tags: formats tags with registry prefix" {
  local versions="1.0.0 1.0.1 2.0.0"
  run get_docker_tags "2.0.0" "$versions" "ghcr.io/user/image"
  [ "$status" -eq 0 ]
  # Should include registry-prefixed tags
  [[ "$output" == *"ghcr.io/user/image:2.0.0"* ]]
  [[ "$output" == *"ghcr.io/user/image:2.0"* ]]
  [[ "$output" == *"ghcr.io/user/image:2"* ]]
  [[ "$output" == *"ghcr.io/user/image:latest"* ]]
}

@test "would_change_tags: returns 0 for globally latest version" {
  local versions="1.0.0 1.0.1 2.0.0"
  run would_change_tags "2.0.0" "$versions"
  [ "$status" -eq 0 ]
}

@test "would_change_tags: returns 0 for latest in lineage" {
  local versions="1.0.0 1.0.1 1.0.2 1.1.0"
  run would_change_tags "1.0.2" "$versions"
  [ "$status" -eq 0 ]
}

@test "would_change_tags: returns 1 for old version" {
  local versions="1.0.0 1.0.1 1.0.2 1.1.0"
  run would_change_tags "1.0.0" "$versions"
  [ "$status" -eq 1 ]
}

@test "get_default_release_tags: lone semver gets full + minor + latest, no bare major" {
  run get_default_release_tags "2.6.10" "2.6.10"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2.6.10"* ]]
  [[ "$output" == *"2.6"* ]]
  [[ "$output" == *"latest"* ]]
  # Bare-major tag must be omitted
  run bash -c 'source .github/scripts/lib/tag-manager.sh; get_default_release_tags "2.6.10" "2.6.10" | grep -qx "2"'
  [ "$status" -ne 0 ]
}

@test "get_default_release_tags: current version need not be in all_versions list" {
  # all_versions defaults to the version itself
  run get_default_release_tags "2.6.10"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2.6.10"* ]]
  [[ "$output" == *"latest"* ]]
}

@test "get_default_release_tags: old semver gets full + minor but not latest" {
  run get_default_release_tags "2.6.9" "2.6.9 2.6.10"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2.6.9"* ]]
  [[ "$output" == *"2.6"* ]]
  [[ "$output" != *"latest"* ]]
}

@test "get_default_release_tags: non-latest minor lineage gets only full version" {
  run get_default_release_tags "2.5.0" "2.5.0 2.5.1 2.6.0"
  [ "$status" -eq 0 ]
  [ "$output" = "2.5.0" ]
}

@test "get_default_release_tags: prerelease gets only full version" {
  run get_default_release_tags "2.6.10-rc1" "2.6.10-rc1"
  [ "$status" -eq 0 ]
  [ "$output" = "2.6.10-rc1" ]
}

@test "get_default_release_tags: image digest yields no tags" {
  run get_default_release_tags "sha256:2f7265c4bcb6bc1a2683bef4396723cffd07c914f647943b74ee8423bb6feb0b" ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "get_default_release_tags: opaque/rolling tag yields no tags" {
  run get_default_release_tags "edge" "edge"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "get_default_release_tags: empty version yields no tags" {
  run get_default_release_tags "" ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "get_default_release_tags: calver gets full + calver partials" {
  run get_default_release_tags "2025.11.13" "2025.11.13"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2025.11.13"* ]]
  [[ "$output" == *"2025.11"* ]]
  [[ "$output" == *"2025"* ]]
}
