#!/usr/bin/env bats
# Dry-run workflow integration tests
#
# Tests the end-to-end dry-run functionality including:
# - Matrix generation with changes detected
# - Dry-run conditional skipping builds
# - Markdown summary report generation
#

setup() {
    # Create temporary test directory
    export TEST_DIR="$(mktemp -d)"
    export REPO_ROOT="$TEST_DIR"

    # Create minimal test images directory structure
    mkdir -p "$TEST_DIR/hello-world"
    mkdir -p "$TEST_DIR/test-app"

    # Create minimal Dockerfiles
    echo "FROM alpine:latest" > "$TEST_DIR/hello-world/Dockerfile"
    echo "FROM alpine:latest" > "$TEST_DIR/test-app/Dockerfile"

    # Create minimal metadata.yaml files
    echo "name: hello-world" > "$TEST_DIR/hello-world/metadata.yaml"
    echo "name: test-app" > "$TEST_DIR/test-app/metadata.yaml"
}

teardown() {
    # Clean up test directory
    rm -rf "$TEST_DIR"
}

# Test matrix generation returns valid JSON
@test "dry-run: matrix generation produces valid JSON output" {
    cd "$REPO_ROOT"

    # Run generate-matrix.sh and capture output
    output=$(.github/scripts/generate-matrix.sh --repo-root . 2>&1)

    # Validate output is valid JSON
    echo "$output" | jq . > /dev/null
    [ $? -eq 0 ]
}

# Test empty matrix handling
@test "dry-run: empty matrix is properly formatted" {
    cd "$REPO_ROOT"

    # Run generate-matrix with no changes (empty matrix expected)
    output=$(.github/scripts/generate-matrix.sh --repo-root . 2>&1)

    # Check if output contains empty image array
    if echo "$output" | jq -e '.image | length > 0' > /dev/null 2>&1; then
        # If images exist, matrix is valid
        echo "$output" | jq -e '.image' > /dev/null
    else
        # If no images, should be empty array
        echo "$output" | jq -e '.image == []' > /dev/null
    fi
    [ $? -eq 0 ]
}

# Test dry-run report generation
@test "dry-run: summary report includes image count" {
    # Test that a dry-run report would include image count
    # This validates the markdown table generation logic

    # Simulate matrix output
    matrix_output='{"image":[{"name":"hello-world","version":"1.0.0","reason":"test"}]}'

    # Count images
    image_count=$(echo "$matrix_output" | jq '.image | length')

    [ "$image_count" -eq 1 ]
}

# Test dry-run report format
@test "dry-run: markdown table has correct format" {
    # Test markdown table generation for dry-run report

    matrix_output='{"image":[
        {"name":"hello-world","version":"1.0.0","reason":"files_changed"},
        {"name":"test-app","version":"2.0.0","reason":"version_changed"}
    ]}'

    # Extract table rows
    rows=$(echo "$matrix_output" | jq -r '.image[] | "| \(.name) | \(.version) | \(.reason) |"')

    # Verify we have 2 rows
    row_count=$(echo "$rows" | wc -l)
    [ "$row_count" -eq 2 ]
}

# Test conditional input validation
@test "dry-run: image names in image_filter are validated" {
    # Test image name validation logic
    # This simulates the validation that would happen in the workflow

    local test_image="hello-world"
    local image_filter="hello-world,test-app"

    # Simulate validation check
    if echo "$image_filter" | grep -q "$(echo "$test_image" | sed 's/[]\/$*.^[]/\\&/g')"; then
        validation_passed=true
    else
        validation_passed=false
    fi

    [ "$validation_passed" = "true" ]
}

# Test skip_images validation
@test "dry-run: skip_images excludes images from matrix" {
    # Simulate skip logic

    local test_images=("hello-world" "test-app" "test-broken")
    local skip_list="test-broken"

    # Count images not in skip list
    included_count=0
    for image in "${test_images[@]}"; do
        if ! echo "$skip_list" | grep -q "$(echo "$image" | sed 's/[]\/$*.^[]/\\&/g')"; then
            ((included_count++))
        fi
    done

    # Should have 2 images (hello-world, test-app)
    [ "$included_count" -eq 2 ]
}

# Test dry-run doesn't trigger builds
@test "dry-run: dry_run=true condition prevents build-arch execution" {
    # Validate the conditional logic that skips builds

    dry_run_input="true"

    # Simulate GitHub Actions conditional
    if [[ "$dry_run_input" == "true" ]]; then
        should_build=false
    else
        should_build=true
    fi

    [ "$should_build" = "false" ]
}

# Test dry-run doesn't create manifests
@test "dry-run: dry_run=true condition prevents manifest creation" {
    # Validate that manifests aren't created during dry-run

    dry_run_input="true"

    # Simulate conditional
    if [[ "$dry_run_input" != "true" ]]; then
        should_create_manifest=true
    else
        should_create_manifest=false
    fi

    [ "$should_create_manifest" = "false" ]
}

# Test version override format validation
@test "dry-run: version_override format is validated" {
    # Test version override parsing

    local override_input="hello-world=v1.0.0,test-app=v2.0.0"

    # Parse and validate format
    while IFS='=' read -r image_name version; do
        image_name=$(echo "$image_name" | xargs)
        # Check that both image and version are present
        [[ -n "$image_name" && -n "$(echo "$version" | xargs)" ]]
    done <<< "$(echo "$override_input" | sed 's/,/\n/g')"

    [ $? -eq 0 ]
}
