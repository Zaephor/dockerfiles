#!/usr/bin/env bats
#
# BATS Tests for Git Commit Detector
#
# Tests GitHub Commits API integration, error handling, and caching
#

setup() {
  export TEST_DIR="$(mktemp -d)"
  export TEST_CONFIG="${TEST_DIR}/metadata.yaml"

  # Create a test config with valid GitHub repo
  cat > "$TEST_CONFIG" <<'EOF'
version_source:
  type: git_commit
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

@test "git-commit detector accepts --config and --image-name" {
  run .github/scripts/detectors/git_commit.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image
  # Should exit 0, 1, or 2 (valid detector behavior)
  [[ $status -eq 0 || $status -eq 1 || $status -eq 2 ]]
}

@test "git-commit detector requires --config argument" {
  run .github/scripts/detectors/git_commit.sh \
    --image-name test-image
  [[ $status -eq 2 ]]
  [[ "$output" =~ "Missing required arguments" ]]
}

@test "git-commit detector requires --image-name argument" {
  run .github/scripts/detectors/git_commit.sh \
    --config "$TEST_CONFIG"
  [[ $status -eq 2 ]]
  [[ "$output" =~ "Missing required arguments" ]]
}

# ============================================================================
# Configuration Parsing Tests
# ============================================================================

@test "git-commit detector rejects config without repo field" {
  local no_repo_config="${TEST_DIR}/no-repo.yaml"
  cat > "$no_repo_config" <<'EOF'
version_source:
  type: git_commit
EOF
  run .github/scripts/detectors/git_commit.sh \
    --config "$no_repo_config" \
    --image-name test-image
  [[ $status -eq 2 ]]
  echo "$output" | jq -e '.error_code == "CONFIG_ERROR"' >/dev/null
}

@test "git-commit detector validates repo format (requires owner/project)" {
  local invalid_repo_config="${TEST_DIR}/invalid-repo.yaml"
  cat > "$invalid_repo_config" <<'EOF'
version_source:
  type: git_commit
  repo: invalid-repo-format
EOF
  run .github/scripts/detectors/git_commit.sh \
    --config "$invalid_repo_config" \
    --image-name test-image
  [[ $status -eq 2 ]]
  echo "$output" | jq -e '.error_code == "CONFIG_ERROR"' >/dev/null
}

@test "git-commit detector accepts valid repo format" {
  local valid_config="${TEST_DIR}/valid-repo.yaml"
  cat > "$valid_config" <<'EOF'
version_source:
  type: git_commit
  repo: owner/valid-project-name
EOF
  run .github/scripts/detectors/git_commit.sh \
    --config "$valid_config" \
    --image-name test-image
  # Should proceed past config validation
  # (may fail on network, but not on config)
  [[ $status -eq 0 || $status -eq 1 ]]
}

@test "git-commit detector accepts optional branch field" {
  local branch_config="${TEST_DIR}/branch.yaml"
  cat > "$branch_config" <<'EOF'
version_source:
  type: git_commit
  repo: owner/test
  branch: main
EOF
  run .github/scripts/detectors/git_commit.sh \
    --config "$branch_config" \
    --image-name test-image
  # Should proceed past config validation
  [[ $status -eq 0 || $status -eq 1 ]]
}

@test "git-commit detector accepts optional auth_token_secret field" {
  local auth_config="${TEST_DIR}/auth.yaml"
  cat > "$auth_config" <<'EOF'
version_source:
  type: git_commit
  repo: owner/test
  auth_token_secret: GITHUB_TOKEN
EOF
  run .github/scripts/detectors/git_commit.sh \
    --config "$auth_config" \
    --image-name test-image
  # Should proceed past config validation (auth failure is exit 1, not 2)
  [[ $status -eq 0 || $status -eq 1 ]]
}

# ============================================================================
# Output Format Tests
# ============================================================================

@test "git-commit detector outputs valid JSON" {
  run .github/scripts/detectors/git_commit.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image
  echo "$output" | jq . >/dev/null
}

@test "git-commit detector includes detector field" {
  run .github/scripts/detectors/git_commit.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image
  echo "$output" | jq -e '.detector == "git-commit"' >/dev/null
}

@test "git-commit detector includes status field" {
  run .github/scripts/detectors/git_commit.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image
  echo "$output" | jq -e '.status' >/dev/null
}

# ============================================================================
# Error Handling Tests
# ============================================================================

@test "git-commit detector returns CONFIG_ERROR on missing repo" {
  local no_repo="${TEST_DIR}/no-repo.yaml"
  cat > "$no_repo" <<'EOF'
version_source:
  type: git_commit
EOF
  run .github/scripts/detectors/git_commit.sh \
    --config "$no_repo" \
    --image-name test-image
  [[ $status -eq 2 ]]
  echo "$output" | jq -e '.error_code == "CONFIG_ERROR"' >/dev/null
}

@test "git-commit detector returns NETWORK_ERROR or NOT_FOUND on bad repo" {
  # Use a repo that doesn't exist (should get 404 from GitHub)
  local bad_repo="${TEST_DIR}/bad-repo.yaml"
  cat > "$bad_repo" <<'EOF'
version_source:
  type: git_commit
  repo: definitely-not-real-org/definitely-not-real-repo-xyz123abc
EOF
  run .github/scripts/detectors/git_commit.sh \
    --config "$bad_repo" \
    --image-name test-image
  [[ $status -eq 1 ]]
  # Should be NOT_FOUND or NETWORK_ERROR
  echo "$output" | jq -e '.error_code == "NOT_FOUND" or .error_code == "NETWORK_ERROR"' >/dev/null
}

# ============================================================================
# Version Format Tests
# ============================================================================

@test "git-commit detector returns 7-character SHA on success" {
  skip "Requires real GitHub API call"
}

@test "git-commit detector includes source_url with full commit SHA" {
  skip "Requires real GitHub API call"
}

# ============================================================================
# Exit Code Tests
# ============================================================================

@test "git-commit detector exits 0/1/2 on any execution" {
  run .github/scripts/detectors/git_commit.sh \
    --config "$TEST_CONFIG" \
    --image-name test-image
  [[ $status -eq 0 || $status -eq 1 || $status -eq 2 ]]
}

@test "git-commit detector exits 2 on fatal config error" {
  local bad_config="${TEST_DIR}/bad.yaml"
  cat > "$bad_config" <<'EOF'
version_source:
  type: git_commit
EOF
  run .github/scripts/detectors/git_commit.sh \
    --config "$bad_config" \
    --image-name test-image
  [[ $status -eq 2 ]]
}

@test "git-commit detector exits 1 on detection failure" {
  local bad_repo="${TEST_DIR}/bad-repo.yaml"
  cat > "$bad_repo" <<'EOF'
version_source:
  type: git_commit
  repo: nonexistent/repo-xyz123
EOF
  run .github/scripts/detectors/git_commit.sh \
    --config "$bad_repo" \
    --image-name test-image
  [[ $status -eq 1 ]]
}

# ============================================================================
# JSON Field Tests
# ============================================================================

@test "git-commit detector failure includes error message" {
  local bad_repo="${TEST_DIR}/bad-repo.yaml"
  cat > "$bad_repo" <<'EOF'
version_source:
  type: git_commit
  repo: nonexistent/repo-xyz123
EOF
  run .github/scripts/detectors/git_commit.sh \
    --config "$bad_repo" \
    --image-name test-image
  echo "$output" | jq -e '.error' >/dev/null
}

@test "git-commit detector failure includes error_code" {
  local bad_repo="${TEST_DIR}/bad-repo.yaml"
  cat > "$bad_repo" <<'EOF'
version_source:
  type: git_commit
  repo: nonexistent/repo-xyz123
EOF
  run .github/scripts/detectors/git_commit.sh \
    --config "$bad_repo" \
    --image-name test-image
  echo "$output" | jq -e '.error_code' >/dev/null
}

@test "git-commit detector failure has null version" {
  local bad_repo="${TEST_DIR}/bad-repo.yaml"
  cat > "$bad_repo" <<'EOF'
version_source:
  type: git_commit
  repo: nonexistent/repo-xyz123
EOF
  run .github/scripts/detectors/git_commit.sh \
    --config "$bad_repo" \
    --image-name test-image
  echo "$output" | jq -e '.version == null' >/dev/null
}

# ============================================================================
# Caching Tests
# ============================================================================

@test "git-commit detector caches successful detection" {
  skip "Requires real GitHub API call"
}

@test "git-commit detector returns cached version on second call" {
  skip "Requires real GitHub API call"
}

@test "git-commit detector sets cached flag in output" {
  skip "Requires real GitHub API call"
}

# ============================================================================
# Timeout Tests
# ============================================================================

@test "git-commit detector respects 30-second timeout" {
  skip "Timeout testing would require network mocking"
}
