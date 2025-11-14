#!/usr/bin/env bats
# Unit tests for conditional-builds.sh script
# Tests conditional build decision logic based on version history and file changes

# Script to test
SCRIPT_PATH=".github/scripts/conditional-builds.sh"

setup() {
    # Create temporary test directory with image structure
    export TEST_DIR="$(mktemp -d)"
    export TEST_REPO="$TEST_DIR/repo"
    mkdir -p "$TEST_REPO"

    # Create test image directory
    export TEST_IMAGE="test-image"
    export IMAGE_DIR="$TEST_REPO/$TEST_IMAGE"
    mkdir -p "$IMAGE_DIR"
}

teardown() {
    # Clean up test directory
    rm -rf "$TEST_DIR"
}

# Helper: Create a minimal history.jsonl file
create_history_file() {
    local image_dir="$1"
    local version="$2"

    mkdir -p "$image_dir"
    cat > "$image_dir/history.jsonl" <<EOF
{"version":"$version","timestamp":"2025-01-01T00:00:00Z","status":"success"}
EOF
}

# Helper: Source the script with required dependencies
load_conditional_builds() {
    # Create minimal stub for logging.sh if not available
    if ! source "$SCRIPT_PATH" 2>/dev/null; then
        # Try to find and source logging.sh
        if [[ -f ".github/scripts/lib/logging.sh" ]]; then
            source ".github/scripts/lib/logging.sh"
            source "$SCRIPT_PATH"
        fi
    fi
}

# Test: should_build_image outputs JSON
@test "should_build_image outputs valid JSON with required fields" {
    load_conditional_builds

    # Call with image that has no history (should build)
    result=$(should_build_image "$TEST_IMAGE" "$TEST_REPO" "1.0.0" 2>/dev/null)

    # Verify result is not empty
    [[ -n "$result" ]]

    # Verify result contains JSON structure
    [[ "$result" =~ "image_name" ]]
    [[ "$result" =~ "should_build" ]]
    [[ "$result" =~ "reason" ]]
    [[ "$result" =~ "version" ]]
}

# Test: should_build_image returns true for new images (no history)
@test "should_build_image returns should_build=true for image with no history" {
    load_conditional_builds

    # Image directory exists but has no history
    mkdir -p "$IMAGE_DIR"

    result=$(should_build_image "$TEST_IMAGE" "$TEST_REPO" "1.0.0" 2>/dev/null)

    # Check JSON output
    [[ "$result" =~ '"should_build":true' ]]
    [[ "$result" =~ '"reason":"no_history"' ]]
}

# Test: should_build_image extracts version field
@test "should_build_image includes version in JSON output" {
    load_conditional_builds

    mkdir -p "$IMAGE_DIR"

    result=$(should_build_image "$TEST_IMAGE" "$TEST_REPO" "2.5.3" 2>/dev/null)

    # Verify version is included in output
    [[ "$result" =~ '"version":"2.5.3"' ]]
}

# Test: should_build_image returns valid JSON that jq can parse
@test "should_build_image output is valid JSON parseable by jq" {
    load_conditional_builds

    mkdir -p "$IMAGE_DIR"

    result=$(should_build_image "$TEST_IMAGE" "$TEST_REPO" "1.0.0" 2>/dev/null)

    # Verify jq can parse the output
    if command -v jq &>/dev/null; then
        should_build=$(echo "$result" | jq -r '.should_build' 2>/dev/null)
        [[ "$should_build" == "true" ]] || [[ "$should_build" == "false" ]]
    fi
}

# Test: should_build_image returns exit code 0 on success
@test "should_build_image returns exit code 0" {
    load_conditional_builds

    mkdir -p "$IMAGE_DIR"

    should_build_image "$TEST_IMAGE" "$TEST_REPO" "1.0.0" 2>/dev/null

    # Verify exit code is 0 (success)
    [[ $? -eq 0 ]]
}
