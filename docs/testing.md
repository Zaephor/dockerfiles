# Testing Guide

Comprehensive testing documentation for the Docker image build system.

## Overview

This project uses [BATS (Bash Automated Testing System)](https://github.com/bats-core/bats-core) for testing shell scripts and build logic.

## Quick Start

### Prerequisites

```bash
# Install BATS
npm install -g bats

# Or via package manager
apt-get install bats  # Debian/Ubuntu
brew install bats-core  # macOS
```

### Run All Tests

```bash
# From project root
bats tests/unit/*.bats

# Run specific test file
bats tests/unit/version-compare.bats

# Verbose output
bats tests/unit/*.bats --verbose
```

## Test Organization

```
tests/
├── unit/                          # Unit tests for shell scripts
│   ├── version-compare.bats       # Version comparison library tests
│   ├── history-query.bats         # History querying tests
│   ├── tag-manager.bats           # Tag management tests
│   ├── rebuild.bats               # Rebuild functionality tests
│   ├── architecture-detection.bats # Architecture detection tests
│   ├── conditional-builds.bats    # Build decision logic tests
│   ├── detectors/                 # Detector-specific tests
│   │   ├── detector-interface.bats
│   │   └── github-releases.bats
│   └── ...
├── integration/                   # Integration tests
│   └── dry-run-workflow.bats      # Workflow integration tests
└── fixtures/                      # Test data and mocks
    ├── history-simple.jsonl       # Sample build history
    ├── history-failures.jsonl     # Failed builds
    ├── history-calver.jsonl       # Calendar versioning
    ├── history-prerelease.jsonl   # Pre-release versions
    ├── manifests/                 # Docker manifest fixtures
    ├── mock-binaries/             # Mock version detection tools
    └── mock-http-apis/            # Mock API responses
```

## Writing Tests

### Basic BATS Test Structure

```bash
#!/usr/bin/env bats

# Load the library to test
load ../../.github/scripts/lib/my-library.sh

setup() {
  # Runs before each test
  export TEST_DIR="$(mktemp -d)"
}

teardown() {
  # Runs after each test
  rm -rf "$TEST_DIR"
}

@test "function name: descriptive test case" {
  run my_function "arg1" "arg2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"expected"* ]]
}
```

### Testing Shell Functions

```bash
@test "compare_versions: 1.0.0 < 1.0.1" {
  run compare_versions "1.0.0" "1.0.1"
  [ "$status" -eq 0 ]  # Function returns 0 for less-than
}

@test "is_calver: detects YYYY.MM.DD format" {
  run is_calver "2025.11.13"
  [ "$status" -eq 0 ]
}

@test "get_major_version: extracts 1 from 1.2.3" {
  run get_major_version "1.2.3"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}
```

### Using Test Fixtures

```bash
setup() {
  export TEST_DIR="$(mktemp -d)"
  export HISTORY_FILE="${TEST_DIR}/history.jsonl"

  # Copy fixture to temporary location
  cp "$(dirname "$BATS_TEST_DIRNAME")"/fixtures/history-simple.jsonl "$HISTORY_FILE"
}

@test "list_versions: returns all versions from history" {
  run list_versions "$HISTORY_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1.0.0"* ]]
}
```

### Testing Error Cases

```bash
@test "validate_rebuild_request: rejects non-existent version" {
  run validate_rebuild_request "test-image" "999.999.999" "$HISTORY_FILE" "$IMAGE_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found in history"* ]]
}
```

## Test Patterns

### Pattern 1: Function Return Codes

BATS captures the exit code in `$status`:

```bash
@test "function succeeds" {
  run my_function
  [ "$status" -eq 0 ]  # Success
}

@test "function fails with error code 2" {
  run my_function_invalid_args
  [ "$status" -eq 2 ]  # Specific error code
}
```

### Pattern 2: Output Validation

BATS captures stdout/stderr in `$output`:

```bash
@test "function outputs expected text" {
  run my_function
  [ "$output" = "exact match" ]
  [[ "$output" == *"substring"* ]]
  [[ "$output" =~ regex.*pattern ]]
}
```

### Pattern 3: JSON Output Validation

Use `jq` to parse and validate JSON output:

```bash
@test "returns valid JSON with version field" {
  run detect_version
  [ "$status" -eq 0 ]

  version=$(echo "$output" | jq -r '.version')
  [[ -n "$version" ]]
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}
```

### Pattern 4: File System Tests

```bash
@test "creates expected directory structure" {
  run setup_image_directory "$TEST_DIR/myimage"
  [ "$status" -eq 0 ]
  [ -d "$TEST_DIR/myimage" ]
  [ -f "$TEST_DIR/myimage/Dockerfile" ]
  [ -f "$TEST_DIR/myimage/metadata.yaml" ]
}
```

## Running Subsets of Tests

```bash
# Run tests matching pattern
bats tests/unit/ --filter "version"

# Run single test
bats tests/unit/version-compare.bats --filter "1.0.0 < 1.0.1"

# Run with timing
bats tests/unit/*.bats --timing

# Run with test count
bats tests/unit/*.bats --count
```

## Continuous Integration

Tests run automatically in GitHub Actions on every push:

```yaml
# .github/workflows/test.yml
- name: Run BATS tests
  run: |
    npm install -g bats
    bats tests/unit/*.bats
```

## Debugging Failed Tests

### Enable Verbose Output

```bash
bats tests/unit/my-test.bats --verbose
```

### Add Debug Statements

```bash
@test "my test" {
  echo "DEBUG: variable value = $MY_VAR" >&3
  run my_function
  echo "DEBUG: status = $status, output = $output" >&3
  [ "$status" -eq 0 ]
}
```

### Run BATS with Trace

```bash
bash -x $(which bats) tests/unit/my-test.bats
```

## Test Coverage

Current test coverage by component:

| Component | Tests | Coverage |
|-----------|-------|----------|
| version-compare.sh | 28 tests | Version parsing, comparison, lineage |
| history-query.sh | 22 tests | History queries, filters, ranges |
| tag-manager.sh | 8 tests | Tag determination, semver/calver |
| rebuild.sh | 7 tests | Rebuild validation, queue generation |
| architecture-detection.sh | 30+ tests | Manifest inspection, GitHub API, URL testing |
| conditional-builds.sh | 15 tests | Build decision logic |
| detector-interface.sh | 20+ tests | Detector contract validation |

Total: **96+ unit tests** covering core functionality

## Adding New Tests

1. Create test file: `tests/unit/my-component.bats`
2. Load library: `load ../../.github/scripts/lib/my-component.sh`
3. Write tests using patterns above
4. Add fixtures to `tests/fixtures/` if needed
5. Run tests: `bats tests/unit/my-component.bats`

## Best Practices

1. **Test one thing per test** - Each `@test` should verify a single behavior
2. **Use descriptive test names** - "function_name: what it does"
3. **Clean up after tests** - Use `teardown()` to remove temp files
4. **Use fixtures** - Don't hardcode test data in tests
5. **Test error cases** - Don't just test success paths
6. **Keep tests fast** - Avoid external API calls, use mocks
7. **Make tests deterministic** - No random values or timestamps

## Common Issues

### Tests fail with "command not found"

**Problem**: Library paths incorrect

**Solution**: Use relative paths from test file location
```bash
load ../../.github/scripts/lib/my-library.sh
```

### Tests pass locally but fail in CI

**Problem**: Missing dependencies or different environment

**Solution**: Check CI logs for missing tools, install in workflow

### Tests are slow

**Problem**: External API calls or expensive operations

**Solution**: Use fixtures and mocks instead of real API calls

## References

- [BATS Documentation](https://bats-core.readthedocs.io/)
- [BATS GitHub Repository](https://github.com/bats-core/bats-core)
- [Shell Testing Best Practices](https://github.com/bats-core/bats-core/wiki/Best-Practices)
- Project-specific: [CONTRIBUTING.md](../CONTRIBUTING.md)
