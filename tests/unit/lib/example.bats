#!/usr/bin/env bats

# Example BATS Test File for Testing Infrastructure
#
# This test demonstrates BATS conventions for shell script testing:
# - setup() function for test isolation
# - teardown() function for cleanup
# - @test blocks for individual test cases
# - Fixture loading and validation
# - Various assertion patterns
#
# Run this test: bats tests/unit/lib/example.bats

setup() {
    # Create test-specific temporary directory
    export TEST_TMPDIR="${BATS_TEST_TMPDIR}/example-$$"
    mkdir -p "$TEST_TMPDIR"

    # Load fixtures directory path
    export FIXTURES_DIR="${BATS_TEST_DIRNAME}/../fixtures"
}

teardown() {
    # Clean up test-specific files and directories
    rm -rf "$TEST_TMPDIR"
}

# Test Case 1: Demonstrate successful test with exit code and output assertions
@test "example test demonstrates successful execution" {
    # Arrange: No setup needed for simple echo test

    # Act: Run a simple command
    run echo "Hello, BATS!"

    # Assert: Check exit code and output
    [ "$status" -eq 0 ]
    [ "$output" = "Hello, BATS!" ]
}

# Test Case 2: Demonstrate file creation and validation
@test "example test can create and validate temporary files" {
    # Arrange: Set up test file path
    local test_file="$TEST_TMPDIR/test.txt"
    local expected_content="Test content"

    # Act: Create test file
    echo "$expected_content" > "$test_file"

    # Assert: Verify file exists and contains expected content
    [ -f "$test_file" ]
    [ -r "$test_file" ]
    [ "$(cat "$test_file")" = "$expected_content" ]
}

# Test Case 3: Demonstrate fixture loading and validation
@test "example test loads and validates fixtures" {
    # Arrange: Define fixture path using BATS variables
    local fixture="${FIXTURES_DIR}/metadata-fallback.yaml"

    # Act & Assert: Verify fixture exists
    [ -f "$fixture" ] || skip "Fixture not found: $fixture"
    [ -r "$fixture" ]

    # Verify fixture contains expected YAML structure
    grep -q "version_source:" "$fixture" || skip "Fixture missing expected field"
}

# Test Case 4: Demonstrate error handling
@test "example test handles command failures gracefully" {
    # Arrange: Command that will fail

    # Act: Run command that should fail
    run false

    # Assert: Verify failure exit code
    [ "$status" -ne 0 ]
}

# Test Case 5: Demonstrate pattern matching on output
@test "example test uses pattern matching for flexible assertions" {
    # Arrange: No setup needed

    # Act: Run command that outputs multiple lines
    run echo -e "Line 1\nLine 2\nLine 3"

    # Assert: Check for pattern in output
    [[ "$output" =~ "Line 1" ]]
    [[ "$output" =~ "Line 2" ]]
    [[ "$output" =~ "Line 3" ]]
}

# Test Case 6: Demonstrate line-by-line output checking
@test "example test can check individual output lines" {
    # Arrange: No setup needed

    # Act: Run command that outputs multiple lines
    run bash -c 'echo "first"; echo "second"; echo "third"'

    # Assert: Check specific lines and total line count
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "first" ]
    [ "${lines[1]}" = "second" ]
    [ "${lines[2]}" = "third" ]
    [ "${#lines[@]}" -eq 3 ]
}

# Test Case 7: Demonstrate JSON fixture usage
@test "example test can parse JSON fixtures with jq" {
    # Arrange: Create sample JSON in test directory
    local json_file="$TEST_TMPDIR/sample.json"
    cat > "$json_file" << 'EOF'
{
  "version": "1.0.0",
  "name": "test-app",
  "tags": ["test", "example"]
}
EOF

    # Act: Parse JSON using jq
    run jq -r '.version' "$json_file"

    # Assert: Verify extraction was successful
    [ "$status" -eq 0 ]
    [ "$output" = "1.0.0" ]
}

# Test Case 8: Demonstrate conditional test skipping
@test "example test can be skipped conditionally" {
    # Skip test if SKIP_EXAMPLE is set (useful for testing skip feature)
    [ -z "$SKIP_EXAMPLE_TEST" ] || skip "SKIP_EXAMPLE_TEST is set"

    # Normal test logic
    run echo "This test was not skipped"
    [ "$status" -eq 0 ]
}
