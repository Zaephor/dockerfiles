#!/usr/bin/env bats
# Unit tests for lib/history.sh append_build_record
# Focuses on empty-version guards that keep history.jsonl trustworthy

setup() {
    export TEST_DIR="$(mktemp -d)"
    export IMAGE_DIR="$TEST_DIR/test-image"
    mkdir -p "$IMAGE_DIR"

    source .github/scripts/lib/history.sh
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "append_build_record writes a valid record for non-empty version" {
    run append_build_record "$IMAGE_DIR" "1.2.3" "abc1234" "main" "amd64" "success"
    [ "$status" -eq 0 ]

    [ -f "$IMAGE_DIR/history.jsonl" ]
    version=$(jq -r '.version' "$IMAGE_DIR/history.jsonl")
    [ "$version" = "1.2.3" ]
}

@test "append_build_record refuses empty version (creates no record)" {
    run append_build_record "$IMAGE_DIR" "" "abc1234" "main" "amd64" "success"
    [ "$status" -ne 0 ]

    # No history file must be created for an empty version
    [ ! -f "$IMAGE_DIR/history.jsonl" ]
}

@test "append_build_record refuses empty version (leaves existing history untouched)" {
    cat > "$IMAGE_DIR/history.jsonl" <<'EOF'
{"version":"1.2.3","timestamp":"2025-01-01T00:00:00Z","commit":"abc1234","branch":"main","manual_trigger":false,"trigger_overrides":null,"architectures":{"amd64":{"status":"success","digest":null,"duration_seconds":null,"start_timestamp":null,"end_timestamp":null,"retry_count":null,"cache_hit_rate":null,"image_size":null,"image_size_change":null}}}
EOF

    run append_build_record "$IMAGE_DIR" "" "def5678" "main" "amd64" "success"
    [ "$status" -ne 0 ]

    # Existing history must be unchanged: still one record with version 1.2.3
    lines=$(wc -l < "$IMAGE_DIR/history.jsonl")
    [ "$lines" -eq 1 ]
    version=$(jq -r '.version' "$IMAGE_DIR/history.jsonl")
    [ "$version" = "1.2.3" ]
}
