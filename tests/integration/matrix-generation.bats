#!/usr/bin/env bats
# Tests for matrix generation script
#
# These tests ensure matrix generation works correctly and catch:
# 1. Unbound variable errors (via set -u)
# 2. Invalid JSON output
# 3. Stdout/stderr mixing
# 4. Correct exit codes

setup() {
  # Set repository root
  export REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export MATRIX_SCRIPT="$REPO_ROOT/.github/scripts/generate-matrix.sh"
}

# ============================================================================
# Basic Functionality Tests
# ============================================================================

@test "matrix generation script exists and is executable" {
  [ -f "$MATRIX_SCRIPT" ]
  [ -x "$MATRIX_SCRIPT" ]
}

@test "matrix generation succeeds with --repo-root flag" {
  run "$MATRIX_SCRIPT" --repo-root "$REPO_ROOT"
  [ "$status" -eq 0 ]
}

@test "matrix generation succeeds with --force-rebuild all" {
  run "$MATRIX_SCRIPT" --repo-root "$REPO_ROOT" --force-rebuild all
  [ "$status" -eq 0 ]
}

# ============================================================================
# JSON Output Validation Tests
# ============================================================================

@test "matrix output is valid JSON" {
  run bash -c "\"$MATRIX_SCRIPT\" --repo-root \"$REPO_ROOT\" --force-rebuild all 2>/dev/null"
  [ "$status" -eq 0 ]

  # Check that output is valid JSON
  run bash -c "echo '$output' | jq . >/dev/null 2>&1"
  [ "$status" -eq 0 ]
}

@test "matrix JSON has correct structure with 'image' key" {
  run bash -c "\"$MATRIX_SCRIPT\" --repo-root \"$REPO_ROOT\" --force-rebuild all 2>/dev/null | jq '.image'"
  [ "$status" -eq 0 ]
  [ "$output" != "null" ]
}

@test "matrix JSON contains expected number of variants" {
  run bash -c "\"$MATRIX_SCRIPT\" --repo-root \"$REPO_ROOT\" --force-rebuild all 2>/dev/null | jq '.image | length'"
  [ "$status" -eq 0 ]
  # Should have at least 2 images (catthehacker/ubuntu-dind variants + hello-world variants)
  [ "$output" -ge 2 ]
}

@test "each matrix entry has required fields" {
  run bash -c "\"$MATRIX_SCRIPT\" --repo-root \"$REPO_ROOT\" --force-rebuild all 2>/dev/null | jq '.image[0] | has(\"name\")'"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run bash -c "\"$MATRIX_SCRIPT\" --repo-root \"$REPO_ROOT\" --force-rebuild all 2>/dev/null | jq '.image[0] | has(\"version\")'"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run bash -c "\"$MATRIX_SCRIPT\" --repo-root \"$REPO_ROOT\" --force-rebuild all 2>/dev/null | jq '.image[0] | has(\"reason\")'"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

# ============================================================================
# Stdout/Stderr Separation Tests
# ============================================================================

@test "stdout contains only valid JSON (no log messages)" {
  # Get stdout only
  run bash -c "\"$MATRIX_SCRIPT\" --repo-root \"$REPO_ROOT\" --force-rebuild all 2>/dev/null"
  [ "$status" -eq 0 ]

  # Every line should be valid JSON (in practice, there should be only 1 line)
  run bash -c "echo '$output' | jq . >/dev/null 2>&1"
  [ "$status" -eq 0 ]

  # Stdout should NOT contain log messages
  run bash -c "echo '$output' | grep -q 'Matrix Decision'"
  [ "$status" -ne 0 ]

  run bash -c "echo '$output' | grep -q 'Matrix Generation'"
  [ "$status" -ne 0 ]
}

@test "stderr contains log messages" {
  # Get stderr only
  run bash -c "\"$MATRIX_SCRIPT\" --repo-root \"$REPO_ROOT\" --force-rebuild all 2>&1 >/dev/null"
  [ "$status" -eq 0 ]

  # Stderr should contain Matrix Generation log
  run bash -c "echo '$output' | grep -q 'Matrix Generation:'"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Error Handling Tests
# ============================================================================

@test "matrix generation fails gracefully with invalid option" {
  run "$MATRIX_SCRIPT" --invalid-option
  [ "$status" -eq 1 ]
}

@test "matrix generation produces error message on stderr for invalid option" {
  run bash -c "\"$MATRIX_SCRIPT\" --invalid-option 2>&1 >/dev/null"
  [ "$status" -eq 1 ]
  run bash -c "echo '$output' | grep -q 'ERROR'"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Unbound Variable Prevention Tests (set -u)
# ============================================================================

@test "script has 'set -u' or 'set -euo pipefail' to catch unbound variables" {
  run bash -c "head -30 \"$MATRIX_SCRIPT\" | grep -E '^set -(e)?u(o)? |^set .*u'"
  [ "$status" -eq 0 ]
}

@test "no unbound variable errors in normal execution" {
  run bash -c "\"$MATRIX_SCRIPT\" --repo-root \"$REPO_ROOT\" 2>&1 | grep -i 'unbound variable'"
  [ "$status" -ne 0 ]
}

@test "no unbound variable errors with force-rebuild" {
  run bash -c "\"$MATRIX_SCRIPT\" --repo-root \"$REPO_ROOT\" --force-rebuild all 2>&1 | grep -i 'unbound variable'"
  [ "$status" -ne 0 ]
}

# ============================================================================
# Per-Variant Tests
# ============================================================================

@test "force-rebuild generates entries with variants" {
  run bash -c "\"$MATRIX_SCRIPT\" --repo-root \"$REPO_ROOT\" --force-rebuild all 2>/dev/null | jq '.image[0] | has(\"variant\")'"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "force-rebuild generates entries with dockerfile paths" {
  run bash -c "\"$MATRIX_SCRIPT\" --repo-root \"$REPO_ROOT\" --force-rebuild all 2>/dev/null | jq '.image[0] | has(\"dockerfile\")'"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "force-rebuild generates entries with architectures" {
  run bash -c "\"$MATRIX_SCRIPT\" --repo-root \"$REPO_ROOT\" --force-rebuild all 2>/dev/null | jq '.image[0] | has(\"architectures\")'"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

# ============================================================================
# Fallback Mode Tests
# ============================================================================

@test "fallback mode still produces valid JSON" {
  # When nothing needs building, it falls back to building all
  run bash -c "\"$MATRIX_SCRIPT\" --repo-root \"$REPO_ROOT\" 2>/dev/null"
  [ "$status" -eq 0 ]

  # Output should still be valid JSON
  run bash -c "echo '$output' | jq . >/dev/null 2>&1"
  [ "$status" -eq 0 ]
}

@test "fallback mode returns exit code 0 (success)" {
  run "$MATRIX_SCRIPT" --repo-root "$REPO_ROOT"
  [ "$status" -eq 0 ]
}
