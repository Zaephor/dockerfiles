#!/usr/bin/env bats
#
# BATS Tests for GitHub Releases Detector
#
# Tests GitHub API integration, error handling, and caching
#

setup() {
  export TEST_DIR="$(mktemp -d)"
  export TEST_CONFIG="${TEST_DIR}/metadata.yaml"

  # Create a test config with valid GitHub repo
  cat > "$TEST_CONFIG" <<'EOF'
version_source:
  type: github-releases
  repo: owner/test-project
EOF
}

teardown() {
  rm -rf "$TEST_DIR"
  # Clear cache
  rm -rf /tmp/version-cache
}

# ============================================================================
# Argument Handling Tests
# ============================================================================

@test "github-releases detector accepts --config and --image-name" {
  run .github/scripts/detectors/github_releases.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image
  # Should exit 0, 1, or 2 (valid detector behavior)
  [[ $status -eq 0 || $status -eq 1 || $status -eq 2 ]]
}

@test "github-releases detector requires --config argument" {
  run .github/scripts/detectors/github_releases.sh \
    --image-name test-image
  [[ $status -eq 2 ]]
  [[ "$output" =~ "Missing required arguments" ]]
}

@test "github-releases detector requires --image-name argument" {
  run .github/scripts/detectors/github_releases.sh \
    --config "$TEST_CONFIG"
  [[ $status -eq 2 ]]
  [[ "$output" =~ "Missing required arguments" ]]
}

# ============================================================================
# Configuration Parsing Tests
# ============================================================================

@test "github-releases detector rejects config without repo field" {
  local no_repo_config="${TEST_DIR}/no-repo.yaml"
  cat > "$no_repo_config" <<'EOF'
version_source:
  type: github-releases
EOF
  run .github/scripts/detectors/github_releases.sh \
    --config "$no_repo_config" \
    --image-name test-image
  [[ $status -eq 2 ]]
  echo "$output" | jq -e '.error_code == "CONFIG_ERROR"' >/dev/null
}

@test "github-releases detector validates repo format (requires owner/project)" {
  local invalid_repo_config="${TEST_DIR}/invalid-repo.yaml"
  cat > "$invalid_repo_config" <<'EOF'
version_source:
  type: github-releases
  repo: invalid-repo-format
EOF
  run .github/scripts/detectors/github_releases.sh \
    --config "$invalid_repo_config" \
    --image-name test-image
  [[ $status -eq 2 ]]
  echo "$output" | jq -e '.error_code == "CONFIG_ERROR"' >/dev/null
}

@test "github-releases detector accepts valid repo format" {
  local valid_config="${TEST_DIR}/valid-repo.yaml"
  cat > "$valid_config" <<'EOF'
version_source:
  type: github-releases
  repo: owner/valid-project-name
EOF
  run .github/scripts/detectors/github_releases.sh \
    --config "$valid_config" \
    --image-name test-image
  # Should proceed past config validation
  # (may fail on network, but not on config)
  [[ $status -eq 0 || $status -eq 1 ]]
}

@test "github-releases detector accepts optional prerelease_filter" {
  local prerelease_config="${TEST_DIR}/prerelease.yaml"
  cat > "$prerelease_config" <<'EOF'
version_source:
  type: github-releases
  repo: owner/test
  prerelease_filter: true
EOF
  run .github/scripts/detectors/github_releases.sh \
    --config "$prerelease_config" \
    --image-name test-image
  # Should proceed past config validation
  [[ $status -eq 0 || $status -eq 1 ]]
}

# ============================================================================
# Output Format Tests
# ============================================================================

@test "github-releases detector outputs valid JSON" {
  run .github/scripts/detectors/github_releases.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image
  echo "$output" | jq . >/dev/null
}

@test "github-releases detector includes detector field" {
  run .github/scripts/detectors/github_releases.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image
  echo "$output" | jq -e '.detector == "github-releases"' >/dev/null
}

@test "github-releases detector includes status field" {
  run .github/scripts/detectors/github_releases.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image
  echo "$output" | jq -e '.status' >/dev/null
}

# ============================================================================
# Error Handling Tests
# ============================================================================

@test "github-releases detector returns CONFIG_ERROR on missing repo" {
  local no_repo="${TEST_DIR}/no-repo.yaml"
  cat > "$no_repo" <<'EOF'
version_source:
  type: github-releases
EOF
  run .github/scripts/detectors/github_releases.sh \
    --config "$no_repo" \
    --image-name test-image
  [[ $status -eq 2 ]]
  echo "$output" | jq -e '.error_code == "CONFIG_ERROR"' >/dev/null
}

@test "github-releases detector returns NETWORK_ERROR or NOT_FOUND on bad repo" {
  # Use a repo that doesn't exist (should get 404 from GitHub)
  local bad_repo="${TEST_DIR}/bad-repo.yaml"
  cat > "$bad_repo" <<'EOF'
version_source:
  type: github-releases
  repo: definitely-not-real-org/definitely-not-real-repo-xyz123abc
EOF
  run .github/scripts/detectors/github_releases.sh \
    --config "$bad_repo" \
    --image-name test-image
  [[ $status -eq 1 ]]
  # Should be NOT_FOUND or NETWORK_ERROR
  echo "$output" | jq -e '.error_code == "NOT_FOUND" or .error_code == "NETWORK_ERROR"' >/dev/null
}

# ============================================================================
# Caching Tests
# ============================================================================

@test "github-releases detector caches successful detection" {
  skip "Requires real GitHub API call"
}

@test "github-releases detector returns cached version on second call" {
  skip "Requires real GitHub API call"
}

@test "github-releases detector sets cached flag in output" {
  skip "Requires real GitHub API call"
}

# ============================================================================
# Exit Code Tests
# ============================================================================

@test "github-releases detector exits 0/1/2 on any execution" {
  run .github/scripts/detectors/github_releases.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image
  [[ $status -eq 0 || $status -eq 1 || $status -eq 2 ]]
}

@test "github-releases detector exits 2 on fatal config error" {
  local bad_config="${TEST_DIR}/bad.yaml"
  cat > "$bad_config" <<'EOF'
version_source:
  type: github-releases
EOF
  run .github/scripts/detectors/github_releases.sh \
    --config "$bad_config" \
    --image-name test-image
  [[ $status -eq 2 ]]
}

@test "github-releases detector exits 1 on detection failure" {
  local bad_repo="${TEST_DIR}/bad-repo.yaml"
  cat > "$bad_repo" <<'EOF'
version_source:
  type: github-releases
  repo: nonexistent/repo-xyz123
EOF
  run .github/scripts/detectors/github_releases.sh \
    --config "$bad_repo" \
    --image-name test-image
  [[ $status -eq 1 ]]
}

# ============================================================================
# JSON Field Tests
# ============================================================================

@test "github-releases detector failure includes error message" {
  local bad_repo="${TEST_DIR}/bad-repo.yaml"
  cat > "$bad_repo" <<'EOF'
version_source:
  type: github-releases
  repo: nonexistent/repo-xyz123
EOF
  run .github/scripts/detectors/github_releases.sh \
    --config "$bad_repo" \
    --image-name test-image
  echo "$output" | jq -e '.error' >/dev/null
}

@test "github-releases detector failure includes error_code" {
  local bad_repo="${TEST_DIR}/bad-repo.yaml"
  cat > "$bad_repo" <<'EOF'
version_source:
  type: github-releases
  repo: nonexistent/repo-xyz123
EOF
  run .github/scripts/detectors/github_releases.sh \
    --config "$bad_repo" \
    --image-name test-image
  echo "$output" | jq -e '.error_code' >/dev/null
}

@test "github-releases detector failure has null version" {
  local bad_repo="${TEST_DIR}/bad-repo.yaml"
  cat > "$bad_repo" <<'EOF'
version_source:
  type: github-releases
  repo: nonexistent/repo-xyz123
EOF
  run .github/scripts/detectors/github_releases.sh \
    --config "$bad_repo" \
    --image-name test-image
  echo "$output" | jq -e '.version == null' >/dev/null
}

# ============================================================================
# Timeout Tests
# ============================================================================

@test "github-releases detector respects 30-second timeout" {
  skip "Timeout testing would require network mocking"
}
