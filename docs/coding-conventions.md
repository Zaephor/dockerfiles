# Shell Script Coding Conventions

This document outlines coding conventions for shell scripts in this repository to prevent common errors and ensure maintainability.

## Strict Mode

**All scripts MUST use strict mode** to catch errors early:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

### What Each Flag Does:

- **`-e` (errexit)**: Exit immediately if any command exits with non-zero status
- **`-u` (nounset)**: Treat unset variables as errors (prevents `$2: unbound variable`)
- **`-o pipefail`**: Exit status of pipeline is the exit status of the last command to exit with non-zero, or zero if all succeed

### Why This Matters:

Without `set -u`, this code silently fails:
```bash
# Bad: typo in variable name goes unnoticed
log_error "$image_name" "$ARHC" "BUILD" "Error"  # $ARHC is undefined
```

With `set -u`, you get an immediate error:
```bash
line 42: ARHC: unbound variable
```

## Stdout vs. Stderr

**Critical Rule**: Functions that return data MUST keep stdout clean.

### Stdout = Data, Stderr = Logs

```bash
# ✅ CORRECT: Logs to stderr, data to stdout
my_function() {
    echo "Processing..." >&2      # Log message
    echo '{"result": "data"}'     # Data output
}

# ❌ WRONG: Mixing logs and data on stdout
my_function() {
    echo "Processing..."          # This breaks JSON parsing!
    echo '{"result": "data"}'
}
```

### Why This Matters:

When piping to `jq` or other parsers:
```bash
# This works - only JSON on stdout
my_function 2>/dev/null | jq .

# This breaks - jq sees "Processing..." mixed with JSON
my_function | jq .  # Error: invalid JSON
```

### Examples:

**Matrix Generation** (returns JSON):
```bash
matrix_log_decision() {
    # Logs go to stderr
    echo "Matrix Decision: [$decision] ..." >&2
}

generate_matrix() {
    # Data goes to stdout
    echo "$matrix_json"
}
```

**Version Detection** (returns version string):
```bash
detect_version() {
    log_debug "Detecting version..." >&2  # Log to stderr
    echo "$version"                        # Version to stdout
}
```

## Variable References

### Always Use Parameter Expansion for Optional Variables

```bash
# ✅ CORRECT: Won't fail if GITHUB_OUTPUT is unset
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "value" >> "$GITHUB_OUTPUT"
fi

# ❌ WRONG: Fails with "unbound variable" if not set
if [[ -n "$GITHUB_OUTPUT" ]]; then
    echo "value" >> "$GITHUB_OUTPUT"
fi
```

### Required vs. Optional Parameters

```bash
my_function() {
    local required_param="$1"           # Required - will fail if not provided (good!)
    local optional_param="${2:-}"       # Optional - empty string if not provided
    local with_default="${3:-default}"  # Optional with default value
}
```

## Function Return Values

### Exit Codes

```bash
# 0 = Success
# 1 = Error (recoverable)
# 2 = Usage error
# >2 = Specific error codes

my_function() {
    if [[ -z "$required_param" ]]; then
        error "Missing required parameter"
        return 2  # Usage error
    fi

    if ! some_operation; then
        error "Operation failed"
        return 1  # Operational error
    fi

    return 0  # Success
}
```

### Data Output

```bash
# Return data via stdout, status via exit code
get_version() {
    local version
    version=$(detect_version) || return 1

    echo "$version"  # Data to stdout
    return 0         # Success status
}

# Use it:
if version=$(get_version); then
    echo "Got version: $version"
else
    error "Version detection failed"
fi
```

## Error Handling

### Use Appropriate Error Functions

```bash
# For general errors (no image/arch context):
error "Something went wrong"

# For build-specific errors (with image/arch context):
log_error "$image_name" "$arch" "BUILD" "Build failed"
```

### Check Command Success

```bash
# ✅ CORRECT: Check if command succeeded
if result=$(some_command 2>&1); then
    process "$result"
else
    error "Command failed: $result"
    return 1
fi

# ❌ WRONG: Doesn't check for errors (with set -e, script exits!)
result=$(some_command)
process "$result"
```

## Testing Requirements

### All Critical Scripts Must Have BATS Tests

Tests should verify:
1. ✅ Correct exit codes
2. ✅ Valid output format (JSON, etc.)
3. ✅ Stdout/stderr separation
4. ✅ No unbound variable errors
5. ✅ Error handling

See `tests/integration/matrix-generation.bats` for a comprehensive example.

### Running Tests

```bash
# Run all tests
bats tests/

# Run specific test file
bats tests/integration/matrix-generation.bats

# Run with verbose output
bats -p tests/integration/matrix-generation.bats
```

## Pre-commit Checks

The `.pre-commit-config.yaml` includes:
- **shellcheck**: Static analysis for shell scripts
- **Shell script linting**: Catches common errors

But pre-commit **cannot** catch:
- Runtime errors (unbound variables, etc.)
- Logic errors (stdout/stderr mixing)
- Output format issues

**Always run BATS tests** before committing critical changes.

## Common Pitfalls

### 1. Forgetting stderr redirection

```bash
# ❌ Wrong: Log message pollutes stdout
log_message() {
    echo "LOG: $1"
}

# ✅ Correct: Log to stderr
log_message() {
    echo "LOG: $1" >&2
}
```

### 2. Not checking for unset variables

```bash
# ❌ Wrong: Crashes if OPTIONAL_VAR not set
if [[ -n "$OPTIONAL_VAR" ]]; then
    use_it "$OPTIONAL_VAR"
fi

# ✅ Correct: Safe check
if [[ -n "${OPTIONAL_VAR:-}" ]]; then
    use_it "$OPTIONAL_VAR"
fi
```

### 3. Mixing data and logs

```bash
# ❌ Wrong: jq will fail
generate_data() {
    echo "Generating..."           # Log on stdout
    echo '{"data": "value"}'        # Data on stdout
}
generate_data | jq .  # ERROR!

# ✅ Correct: Separate channels
generate_data() {
    echo "Generating..." >&2        # Log to stderr
    echo '{"data": "value"}'        # Data to stdout
}
generate_data | jq .  # Works!
```

## Enforcement

These conventions are enforced by:
1. **Code Review**: Reviewers check for compliance
2. **BATS Tests**: Tests verify behavior
3. **Pre-commit**: Catches some issues automatically
4. **CI**: Runs full test suite on every commit

## Migration

Existing scripts should be updated to follow these conventions:
1. Add `set -euo pipefail` if missing
2. Move logs to stderr
3. Add parameter expansion for optional variables
4. Add BATS tests for critical paths
