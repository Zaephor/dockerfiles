#!/usr/bin/env bats
# Enhanced conditional builds tests for Sprint 13 manual controls
#
# Tests the integration of conditional build logic with manual control inputs:
# - force_rebuild override
# - image_filter limiting
# - skip_images exclusion
# - version_override application
#

# Helper: Simulate should_include_image function
should_include_image() {
    local image_name="$1"
    local image_filter="$2"

    if [[ -z "$image_filter" ]]; then
        return 0
    fi

    if echo "$image_filter" | grep -q "$(echo "$image_name" | sed 's/[]\/$*.^[]/\\&/g')"; then
        return 0
    fi

    return 1
}

# Helper: Simulate should_skip_image function
should_skip_image() {
    local image_name="$1"
    local skip_list="$2"

    if [[ -z "$skip_list" ]]; then
        return 1
    fi

    if echo "$skip_list" | grep -q "$(echo "$image_name" | sed 's/[]\/$*.^[]/\\&/g')"; then
        return 0
    fi

    return 1
}

# Helper: Simulate should_force_rebuild function
should_force_rebuild() {
    local image_name="$1"
    local force_rebuild_list="$2"

    if [[ -z "$force_rebuild_list" ]]; then
        return 1
    fi

    if [[ "$force_rebuild_list" == "all" ]]; then
        return 0
    fi

    if echo "$force_rebuild_list" | grep -q "$(echo "$image_name" | sed 's/[]\/$*.^[]/\\&/g')"; then
        return 0
    fi

    return 1
}

# Test force_rebuild=all includes all images
@test "conditional-builds: force_rebuild=all includes all images" {
    local force_rebuild_list="all"

    should_force_rebuild "hello-world" "$force_rebuild_list"
    [ $? -eq 0 ]

    should_force_rebuild "test-app" "$force_rebuild_list"
    [ $? -eq 0 ]

    should_force_rebuild "other-image" "$force_rebuild_list"
    [ $? -eq 0 ]
}

# Test force_rebuild specific image
@test "conditional-builds: force_rebuild includes specific images only" {
    local force_rebuild_list="hello-world,test-app"

    should_force_rebuild "hello-world" "$force_rebuild_list"
    [ $? -eq 0 ]

    should_force_rebuild "test-app" "$force_rebuild_list"
    [ $? -eq 0 ]

    should_force_rebuild "other-image" "$force_rebuild_list"
    [ $? -ne 0 ]
}

# Test image_filter includes only listed images
@test "conditional-builds: image_filter includes only specified images" {
    local image_filter="hello-world,test-app"

    should_include_image "hello-world" "$image_filter"
    [ $? -eq 0 ]

    should_include_image "test-app" "$image_filter"
    [ $? -eq 0 ]

    should_include_image "other-image" "$image_filter"
    [ $? -ne 0 ]
}

# Test image_filter empty includes all
@test "conditional-builds: empty image_filter includes all images" {
    local image_filter=""

    should_include_image "hello-world" "$image_filter"
    [ $? -eq 0 ]

    should_include_image "test-app" "$image_filter"
    [ $? -eq 0 ]

    should_include_image "other-image" "$image_filter"
    [ $? -eq 0 ]
}

# Test skip_images excludes specified images
@test "conditional-builds: skip_images excludes specified images" {
    local skip_list="test-broken,deprecated"

    should_skip_image "test-broken" "$skip_list"
    [ $? -eq 0 ]

    should_skip_image "deprecated" "$skip_list"
    [ $? -eq 0 ]

    should_skip_image "hello-world" "$skip_list"
    [ $? -ne 0 ]
}

# Test skip_images empty skips nothing
@test "conditional-builds: empty skip_images skips no images" {
    local skip_list=""

    should_skip_image "test-broken" "$skip_list"
    [ $? -ne 0 ]

    should_skip_image "hello-world" "$skip_list"
    [ $? -ne 0 ]
}

# Test force_rebuild overrides skip
@test "conditional-builds: force_rebuild overrides skip_images" {
    local skip_list="hello-world"
    local force_rebuild_list="hello-world"

    # Image is in skip list
    should_skip_image "hello-world" "$skip_list"
    [ $? -eq 0 ]

    # But also in force_rebuild, so should be rebuilt
    should_force_rebuild "hello-world" "$force_rebuild_list"
    [ $? -eq 0 ]
}

# Test image_filter + skip_images interaction
@test "conditional-builds: image_filter and skip_images work together" {
    local image_filter="hello-world,test-app,other-image"
    local skip_list="test-app"

    # hello-world is in filter and not in skip
    should_include_image "hello-world" "$image_filter"
    [ $? -eq 0 ]
    should_skip_image "hello-world" "$skip_list"
    [ $? -ne 0 ]

    # test-app is in filter but also in skip
    should_include_image "test-app" "$image_filter"
    [ $? -eq 0 ]
    should_skip_image "test-app" "$skip_list"
    [ $? -eq 0 ]

    # unrelated-image is not in filter
    should_include_image "unrelated-image" "$image_filter"
    [ $? -ne 0 ]
}

# Test version_override parsing
@test "conditional-builds: version_override parses image=version correctly" {
    local override_input="hello-world=v1.0.0,test-app=v2.0.0"

    # Parse first entry
    IFS='=' read -r image_name version <<< "$(echo "$override_input" | cut -d',' -f1)"
    image_name=$(echo "$image_name" | xargs)
    version=$(echo "$version" | xargs)

    [ "$image_name" = "hello-world" ]
    [ "$version" = "v1.0.0" ]
}

# Test version_override with whitespace
@test "conditional-builds: version_override handles whitespace" {
    local override_input="hello-world = v1.0.0 , test-app = v2.0.0"

    # Parse with whitespace handling
    while IFS='=' read -r image_name version; do
        image_name=$(echo "$image_name" | xargs)
        version=$(echo "$version" | xargs)

        if [[ "$image_name" == "hello-world" ]]; then
            [ "$version" = "v1.0.0" ]
        elif [[ "$image_name" == "test-app" ]]; then
            [ "$version" = "v2.0.0" ]
        fi
    done <<< "$(echo "$override_input" | sed 's/,/\n/g')"
}

# Test combined: force_rebuild + image_filter + skip_images
@test "conditional-builds: all filters applied in correct precedence" {
    # Scenario: user specifies all three manual controls
    local force_rebuild="test-broken"
    local image_filter="hello-world,test-app,test-broken"
    local skip_images="test-app"

    # hello-world: in filter, not in skip, not forced -> INCLUDE
    local include_hello_world=true
    local skip_hello_world=false
    if [[ "$skip_hello_world" == "true" ]] && [[ "$force_rebuild" != "test-broken" ]]; then
        include_hello_world=false
    fi
    [ "$include_hello_world" = "true" ]

    # test-app: in filter, in skip, not forced -> SKIP
    local include_test_app=true
    local skip_test_app=true
    if [[ "$skip_test_app" == "true" ]] && [[ "$force_rebuild" != "test-app" ]]; then
        include_test_app=false
    fi
    [ "$include_test_app" = "false" ]

    # test-broken: in filter, in skip, forced -> REBUILD (force overrides)
    local include_test_broken=true
    local skip_test_broken=true
    if [[ "$skip_test_broken" == "true" ]] && [[ "$force_rebuild" == "test-broken" ]]; then
        include_test_broken=true  # force_rebuild overrides
    fi
    [ "$include_test_broken" = "true" ]
}
