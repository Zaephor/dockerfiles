#!/usr/bin/env bash
# test-history-workflow.sh - Pre-commit test for history.jsonl workflow
#
# This test simulates the complete CI workflow to ensure history files
# are created correctly with no empty lines or invalid JSON.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

FAILED=0

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Testing history.jsonl workflow..."
echo ""

# Test 1: Create new history file
test_create_new_file() {
  echo -n "  [1/5] Creating new history file... "

  local test_dir="$TEST_DIR/test1"
  mkdir -p "$test_dir"

  "$SCRIPT_DIR/record-build-history.sh" \
    --image-dir "$test_dir" \
    --version "sha256:test123" \
    --commit "abc123" \
    --branch "main" \
    --arch "amd64" \
    --build-status "success" \
    --digest "sha256:digest123" \
    --retry-count "0" \
    --cache-hit-rate "85.5" \
    --image-size "1234567" >/dev/null 2>&1

  local history_file="$test_dir/history.jsonl"

  # Validate file exists
  if [ ! -f "$history_file" ]; then
    echo -e "${RED}FAILED${NC} - File not created"
    return 1
  fi

  # Validate no empty lines
  if grep -q '^$' "$history_file"; then
    echo -e "${RED}FAILED${NC} - Contains empty lines"
    return 1
  fi

  # Validate JSON
  if ! jq empty "$history_file" 2>/dev/null; then
    echo -e "${RED}FAILED${NC} - Invalid JSON"
    return 1
  fi

  # Validate exactly 1 line
  local lines=$(wc -l < "$history_file")
  if [ "$lines" -ne 1 ]; then
    echo -e "${RED}FAILED${NC} - Expected 1 line, got $lines"
    return 1
  fi

  echo -e "${GREEN}OK${NC}"
}

# Test 2: Merge parallel builds
test_merge_parallel_builds() {
  echo -n "  [2/5] Merging parallel builds... "

  local artifacts_dir="$TEST_DIR/test2/artifacts"
  mkdir -p "$artifacts_dir"

  # Create amd64 artifact
  local amd64_dir="$artifacts_dir/history-test-amd64"
  mkdir -p "$amd64_dir"
  echo "test-image" > "$amd64_dir/image_path.txt"
  cat > "$amd64_dir/history.jsonl" <<'EOF'
{"version":"sha256:abc","timestamp":"2025-01-01T00:00:00Z","commit":"abc","branch":"main","manual_trigger":false,"trigger_overrides":null,"architectures":{"amd64":{"status":"success","digest":"sha256:amd64"}}}
EOF

  # Create arm64 artifact
  local arm64_dir="$artifacts_dir/history-test-arm64"
  mkdir -p "$arm64_dir"
  echo "test-image" > "$arm64_dir/image_path.txt"
  cat > "$arm64_dir/history.jsonl" <<'EOF'
{"version":"sha256:abc","timestamp":"2025-01-01T00:00:00Z","commit":"abc","branch":"main","manual_trigger":false,"trigger_overrides":null,"architectures":{"arm64":{"status":"success","digest":"sha256:arm64"}}}
EOF

  # Run merge
  cd "$TEST_DIR/test2"
  "$SCRIPT_DIR/merge-history-artifacts.sh" "$artifacts_dir" >/dev/null 2>&1

  local merged_file="test-image/history.jsonl"

  # Validate merged file
  if [ ! -f "$merged_file" ]; then
    echo -e "${RED}FAILED${NC} - Merged file not created"
    return 1
  fi

  # Validate exactly 1 line (not 2)
  local lines=$(wc -l < "$merged_file")
  if [ "$lines" -ne 1 ]; then
    echo -e "${RED}FAILED${NC} - Expected 1 merged line, got $lines"
    return 1
  fi

  # Validate both architectures present
  local arch_count=$(jq '.architectures | keys | length' "$merged_file")
  if [ "$arch_count" -ne 2 ]; then
    echo -e "${RED}FAILED${NC} - Expected 2 architectures, got $arch_count"
    return 1
  fi

  echo -e "${GREEN}OK${NC}"
}

# Test 3: Handle GitHub Actions edge cases
test_github_actions_edge_cases() {
  echo -n "  [3/5] Handling GitHub Actions edge cases... "

  local test_dir="$TEST_DIR/test3"
  mkdir -p "$test_dir"

  # Test with "null" string
  "$SCRIPT_DIR/record-build-history.sh" \
    --image-dir "$test_dir" \
    --version "sha256:test" \
    --commit "abc" \
    --branch "main" \
    --arch "amd64" \
    --build-status "success" \
    --cache-hit-rate "null" \
    --image-size "undefined" >/dev/null 2>&1

  local history_file="$test_dir/history.jsonl"

  # Validate JSON is still valid
  if ! jq empty "$history_file" 2>/dev/null; then
    echo -e "${RED}FAILED${NC} - Invalid JSON with null/undefined values"
    return 1
  fi

  # Validate null strings converted to JSON null
  local cache_val=$(jq -r '.architectures.amd64.cache_hit_rate' "$history_file")
  if [ "$cache_val" != "null" ]; then
    echo -e "${RED}FAILED${NC} - Expected null, got $cache_val"
    return 1
  fi

  echo -e "${GREEN}OK${NC}"
}

# Test 4: Empty lines are filtered
test_empty_line_filtering() {
  echo -n "  [4/5] Filtering empty lines... "

  local test_dir="$TEST_DIR/test4"
  mkdir -p "$test_dir"

  # Create a corrupted history file with empty lines
  cat > "$test_dir/history.jsonl" <<'EOF'

{"version":"sha256:old","timestamp":"2025-01-01T00:00:00Z","commit":"old","branch":"main","manual_trigger":false,"trigger_overrides":null,"architectures":{"amd64":{"status":"success","digest":"sha256:old"}}}

EOF

  # Add new record (should filter empty lines)
  "$SCRIPT_DIR/record-build-history.sh" \
    --image-dir "$test_dir" \
    --version "sha256:new" \
    --commit "new" \
    --branch "main" \
    --arch "amd64" \
    --build-status "success" >/dev/null 2>&1

  local history_file="$test_dir/history.jsonl"

  # Validate no empty lines
  if grep -q '^$' "$history_file"; then
    echo -e "${RED}FAILED${NC} - Empty lines not filtered"
    cat -A "$history_file"
    return 1
  fi

  # Validate 2 records (old + new)
  local lines=$(wc -l < "$history_file")
  if [ "$lines" -ne 2 ]; then
    echo -e "${RED}FAILED${NC} - Expected 2 lines, got $lines"
    return 1
  fi

  echo -e "${GREEN}OK${NC}"
}

# Test 5: Update existing record with new architecture
test_update_existing_record() {
  echo -n "  [5/5] Updating existing record... "

  local test_dir="$TEST_DIR/test5"
  mkdir -p "$test_dir"

  # Create initial record with amd64
  "$SCRIPT_DIR/record-build-history.sh" \
    --image-dir "$test_dir" \
    --version "sha256:same" \
    --commit "abc" \
    --branch "main" \
    --arch "amd64" \
    --build-status "success" >/dev/null 2>&1

  # Add arm64 to same version
  "$SCRIPT_DIR/record-build-history.sh" \
    --image-dir "$test_dir" \
    --version "sha256:same" \
    --commit "abc" \
    --branch "main" \
    --arch "arm64" \
    --build-status "success" >/dev/null 2>&1

  local history_file="$test_dir/history.jsonl"

  # Validate still 1 line (updated, not appended)
  local lines=$(wc -l < "$history_file")
  if [ "$lines" -ne 1 ]; then
    echo -e "${RED}FAILED${NC} - Expected 1 line, got $lines"
    return 1
  fi

  # Validate both architectures in same record
  local arch_count=$(jq '.architectures | keys | length' "$history_file")
  if [ "$arch_count" -ne 2 ]; then
    echo -e "${RED}FAILED${NC} - Expected 2 architectures, got $arch_count"
    return 1
  fi

  echo -e "${GREEN}OK${NC}"
}

# Run all tests
test_create_new_file || FAILED=1
test_merge_parallel_builds || FAILED=1
test_github_actions_edge_cases || FAILED=1
test_empty_line_filtering || FAILED=1
test_update_existing_record || FAILED=1

echo ""
if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ All history workflow tests passed${NC}"
  exit 0
else
  echo -e "${RED}✗ History workflow tests failed${NC}"
  exit 1
fi
