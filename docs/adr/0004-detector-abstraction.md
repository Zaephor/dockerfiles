# 0004. Pluggable Version Detector Abstraction

**Status**: Accepted
**Date**: 2025-11-13
**Decision Maker(s)**: Project Maintainer

## Context

### Background

Different upstream projects publish versions in different ways:
- GitHub Releases (kubectl, helm, prometheus)
- GitHub Tags (alternative to releases)
- Binary `--version` output (go, rust, node)
- Docker registry tags (python, node official images)
- HTTP JSON APIs (custom sources)
- RSS feeds, version files, etc.

Early versions hardcoded version detection logic for each image, creating maintenance burden and limiting extensibility.

### Problem Statement

Without pluggable detection:
1. Adding new upstream source type requires modifying core workflow
2. Code duplication for common patterns
3. Hard to maintain consistency across detectors
4. Difficult for contributors to add their own detectors

## Decision

Implement pluggable detector abstraction: each version source type has a separate shell script in `.github/scripts/detectors/` that implements standard interface.

### Implementation Details

**Directory Structure**:
```
.github/scripts/detectors/
├── github_releases.sh
├── binary_version.sh
├── docker_tag.sh
├── http-json.sh
└── README.md
```

**Detector Interface**:

```bash
#!/usr/bin/env bash
# Detects version for IMAGE_DIR based on metadata.yaml source config

# Input:  IMAGE_DIR (path to image directory)
# Output: Version string to stdout
# Exit:   0 = success, 1 = failure
# Read:   metadata.yaml in IMAGE_DIR

IMAGE_DIR="$1"
METADATA_FILE="$IMAGE_DIR/metadata.yaml"

# Extract source config from metadata
GITHUB_REPO=$(yq eval '.source.github_repo' "$METADATA_FILE")

# Detect version (call API, etc.)
# ... detection logic ...

echo "1.2.3"  # Output version
exit 0
```

**Metadata Configuration**:
```yaml
version_source: github_releases    # Determines which detector to call
source:                             # Source-specific config
  github_repo: owner/repo
  version_regex: ^v(.+)$
```

**Workflow Integration**:
```bash
DETECTOR=".github/scripts/detectors/${VERSION_SOURCE}.sh"
if [ -f "$DETECTOR" ]; then
    VERSION=$("$DETECTOR" "$IMAGE_DIR")
else
    echo "ERROR: Unknown version_source: $VERSION_SOURCE"
fi
```

### Key Principles Applied

- **Principle 10**: Scale Through Configuration - New detectors added as configuration, not code
- **Principle 9**: Version Detection Pluggability - Direct implementation of this principle

## Consequences

### Positive

- **Extensibility** - New detectors added without modifying workflow
- **Consistency** - All detectors follow same interface and error handling
- **Testability** - Each detector tested independently with BATS
- **Maintainability** - Clear separation of concerns
- **Community contribution** - Contributors can add detectors via pull requests

### Negative

- **Shell script complexity** - Shell scripts handle API calls, parsing, error handling
- **Testing burden** - Each detector needs unit tests
- **API dependency** - Detectors depend on external APIs (GitHub, Docker Hub)
- **Error handling** - Each detector must handle failures gracefully

## Alternatives Considered

### Alternative 1: Monolithic Detector

**Description**: Single script handling all version source types with conditional logic.

**Rejected Because**:
- Hard to maintain (script grows very large)
- Hard to test (all tests in one file)
- Hard to extend (need to modify central script for each new type)
- Violates single responsibility principle

### Alternative 2: External Process/Tool

**Description**: Use external tool/language for detectors (Python, Go, etc.).

**Rejected Because**:
- Adds language dependency
- Harder to debug (need Python/Go/etc installed)
- Complicates local development
- Bash is already used for other scripts

### Alternative 3: Hard-Coded Detector Selection

**Description**: Determine detector type internally, no explicit configuration.

**Rejected Because**:
- Can't handle projects using multiple detection methods
- Users can't override detection (if needed)
- Fails for uncommon source types (HTTP APIs)

## Adding New Detectors

1. Create `.github/scripts/detectors/{source-type}.sh`
2. Implement standard interface (read metadata, output version, exit code 0/1)
3. Add source type to enum in validation script
4. Write BATS unit tests
5. Document in YAML configuration reference

Example: Adding `http-json` detector

```bash
#!/usr/bin/env bash
# Detect version from HTTP JSON API
set -euo pipefail

IMAGE_DIR="$1"
METADATA_FILE="$IMAGE_DIR/metadata.yaml"

URL=$(yq eval '.source.url' "$METADATA_FILE")
JSON_PATH=$(yq eval '.source.json_path' "$METADATA_FILE")

# Fetch and parse
if VERSION=$(curl -s "$URL" | jq -r "$JSON_PATH"); then
    echo "$VERSION"
    exit 0
else
    exit 1
fi
```

## Detector Testing

All detectors have BATS test coverage:

```bash
@test "github-releases detector fetches latest release" {
    run .github/scripts/detectors/github-releases.sh test-image-dir
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]  # Semver format
}
```

## References

- Detector scripts: [.github/scripts/detectors/](../../.github/scripts/detectors/)
- Detector interface: See `.github/scripts/detectors/` directory for implementation examples
- YAML configuration reference: [docs/yaml-config-reference.md](../yaml-config-reference.md)
