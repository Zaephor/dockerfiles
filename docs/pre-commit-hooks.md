# Pre-commit Hooks

This project uses [pre-commit](https://pre-commit.com/) to enforce code quality and consistency before commits.

## What Gets Checked

### GitHub Actions Workflows
- **actionlint**: Validates workflow syntax, context variables, expressions
  - Checks for typos in context variables (`github.`, `matrix.`, etc.)
  - Validates expression syntax
  - Ensures required fields are present

### Dockerfiles
- **hadolint**: Enforces Docker best practices
  - Pin base image versions
  - Avoid unnecessary packages
  - Use specific versions in package installs
  - Layer optimization

### Shell Scripts
- **shellcheck**: Catches common bash errors
  - Unquoted variables
  - Incorrect array usage
  - Portability issues
  - Logic errors

### YAML Files
- **yamllint**: Style and syntax checking
  - Indentation consistency
  - Key uniqueness
  - Line length (warning only)

### Markdown Files
- **markdownlint**: Documentation consistency
  - Heading hierarchy
  - List formatting
  - Line length (warnings)

### Documentation References
- **validate-doc-references**: Validates internal markdown links
  - Checks links in README.md, CONTRIBUTING.md, docs/
  - Handles relative paths and anchor fragments
  - Prevents broken documentation links

### Project-Specific Tests
- **test-history-workflow**: Validates build history tracking
  - Ensures history.jsonl files are valid JSON
  - Checks for no empty lines
  - Tests merge-history-artifacts.sh logic
- **test-matrix-generation**: Validates build matrix generation
  - Tests matrix-generation with BATS
  - Validates JSON format and stdout/stderr separation
  - Checks for unbound variables

### General
- Remove trailing whitespace
- Ensure files end with newline
- Normalize line endings (LF)
- Prevent large files
- Check for merge conflicts

## Installation

### Prerequisites
```bash
# Install pre-commit
pip install pre-commit

# Or via homebrew (macOS)
brew install pre-commit

# Or via apt (Ubuntu/Debian)
sudo apt install pre-commit
```

### Setup
```bash
# Install the git hook scripts
pre-commit install

# (Optional) Run against all files initially
pre-commit run --all-files
```

## Usage

### Automatic (Recommended)
Once installed, hooks run automatically on `git commit`:

```bash
git add .
git commit -m "your message"
# Pre-commit hooks will run automatically
```

If any hooks fail:
1. Fix the reported issues
2. Stage the fixes: `git add <fixed-files>`
3. Commit again: `git commit -m "your message"`

### Manual
Run hooks manually on staged files:
```bash
pre-commit run
```

Run hooks on all files:
```bash
pre-commit run --all-files
```

Run a specific hook:
```bash
pre-commit run actionlint                # Check workflows
pre-commit run hadolint-docker           # Check Dockerfiles
pre-commit run shellcheck                # Check shell scripts
pre-commit run yamllint                  # Check YAML files
pre-commit run validate-doc-references   # Check documentation links
pre-commit run test-matrix-generation    # Test matrix generation
pre-commit run test-history-workflow     # Test history tracking
```

## Skipping Hooks

### Skip all hooks (use sparingly)
```bash
git commit --no-verify -m "emergency fix"
```

### Skip specific hooks
```bash
SKIP=shellcheck git commit -m "message"
SKIP=shellcheck,hadolint-docker git commit -m "message"
```

## Updating Hooks

Update to latest hook versions:
```bash
pre-commit autoupdate
```

## Configuration Files

- `.pre-commit-config.yaml` - Hook configuration
- `.yamllint.yaml` - YAML linting rules
- `.hadolint.yaml` - Dockerfile linting rules
- `.markdownlint.yaml` - Markdown linting rules

## Common Issues

### actionlint: Unknown context variable
**Problem:** `github.event.inputs.foo` shows as invalid
**Solution:** Variable might be mistyped, or only available in specific trigger types

### hadolint: Pin versions
**Problem:** `DL3007: Using latest tag`
**Solution:** Specify exact version: `FROM alpine:3.19` instead of `FROM alpine:latest`

### shellcheck: Quote variables
**Problem:** `SC2086: Quote to prevent word splitting`
**Solution:** Change `$VAR` to `"$VAR"`

### yamllint: Line too long
**Problem:** `line too long (> 200 characters)`
**Solution:** Break into multiple lines or use YAML multiline strings

## CI Integration

Pre-commit hooks also run in CI via the `lint` job:
- Ensures all commits pass linting
- Catches issues that might be skipped locally
- Uses same configuration as local hooks

## Disabling Hooks Locally

If you need to disable hooks locally (not recommended):
```bash
# Uninstall hooks
pre-commit uninstall

# Reinstall later
pre-commit install
```
