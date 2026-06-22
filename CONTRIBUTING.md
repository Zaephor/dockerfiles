# Contributing Guide

Welcome! This guide explains how to contribute to the Docker Image Build System, whether you're adding a new image, creating a new version detector, or improving documentation.

## Quick Links

- **Adding a new image?** → See "How to Add a New Image" section
- **Stuck?** → Check [docs/troubleshooting.md](docs/troubleshooting.md)
- **Want to understand the system?** → Read [README.md](README.md)
- **Need configuration reference?** → See [docs/yaml-config-reference.md](docs/yaml-config-reference.md)

## How to Add a New Image (10 Minutes)

### Step 1: Choose Your Pattern

Find an example matching your upstream source:

- **GitHub Releases** → `cp -r docs/examples/github-release my-image`
- **Binary with --version** → `cp -r docs/examples/binary-version my-tool`
- **Docker Registry Tag** → `cp -r docs/examples/docker-tag my-base`
- **Multiple Variants** → `cp -r docs/examples/multi-variant my-image`

See [docs/examples/README.md](docs/examples/README.md) for detailed descriptions of each pattern.

### Step 2: Customize Dockerfile

Edit `my-image/Dockerfile` with your:
- Base image
- Installation commands
- Version labels (recommended: `org.opencontainers.image.version=$VERSION`)
- Entry point

**Linting**: Must pass hadolint (Dockerfile best practices)

```bash
.github/scripts/local-tools/lint-dockerfile.sh my-image
```

### Step 3: Create metadata.yaml

Copy and customize the metadata from your chosen example. Required fields:

```yaml
name: my-image                    # Image name for tagging
version_source:                   # How to detect version
  type: github_releases           # Detector type
  repo: owner/repo                # Repository for version detection

# Optional fields (defaults used if omitted):
architectures: [amd64, arm64]     # Override auto-detection
variants: [alpine, slim]          # Alternative Dockerfile.variant names
```

**Validation**: Must pass schema validation

```bash
.github/scripts/local-tools/validate-metadata.sh my-image
```

See [docs/yaml-config-reference.md](docs/yaml-config-reference.md) for all available fields with examples.

### Step 4: Test Locally (Optional but Recommended)

Run local validation before pushing to GitHub:

```bash
# Validate metadata.yaml syntax and schema
.github/scripts/local-tools/validate-metadata.sh my-image

# Test version detection
.github/scripts/local-tools/test-version-detection.sh my-image

# Check if image would be built (conditional build logic)
.github/scripts/local-tools/check-conditional-build.sh my-image

# Lint Dockerfile(s)
.github/scripts/local-tools/lint-dockerfile.sh my-image
```

See [Local Testing Workflow](#local-testing-workflow) below for details on each tool.

### Step 5: Commit and Push

```bash
git add my-image/
git commit -m "Add my-image: Docker image for XYZ"
git push
```

**Automated CI** will:
1. ✓ Lint your Dockerfile and YAML
2. ✓ Validate metadata.yaml schema
3. ✓ Detect version from upstream
4. ✓ Build image for amd64 and arm64
5. ✓ Push to GHCR
6. ✓ Create manifest list
7. ✓ Update build history

### Step 6: Submit Pull Request (if Contributing to Repository)

1. Create PR with description of what the image does
2. CI will validate and build automatically
3. Reviewer will check configuration and Dockerfile
4. Merge when approved

## Local Testing Workflow

### validate-metadata.sh

Validates metadata.yaml file before pushing.

```bash
.github/scripts/local-tools/validate-metadata.sh IMAGE_NAME

# Exit codes:
# 0 = Valid
# 1 = Schema validation failed
# 2 = Missing dependencies (yq, jq)
# 3 = Invalid arguments
# 4 = metadata.yaml not found
```

**Checks**:
- YAML syntax is valid
- Required fields present: `name`, `version_source`
- `version_source.type` value is one of: github_releases, git_commit, docker_tag, docker_digest, binary_version, http_json
- Architectures (if specified) are valid: amd64, arm64, 386, ppc64le, s390x
- Referenced Dockerfile variants exist

**Example**:

```bash
$ .github/scripts/local-tools/validate-metadata.sh hello-world
✓ YAML syntax valid
✓ Required fields present: name, version_source
✓ version_source.type value valid: github_releases
✓ Architectures not specified (will auto-detect)
✓ Metadata validation passed
```

### test-version-detection.sh

Tests version detection by running your configured detector locally.

```bash
.github/scripts/local-tools/test-version-detection.sh IMAGE_NAME

# Exit codes:
# 0 = Version detected successfully
# 1 = Detection failed
# 2 = Missing dependencies
# 3 = Invalid arguments
# 4 = metadata.yaml or detector not found
```

**Requires**:
- metadata.yaml with `version_source` field
- Detector script exists for your source type
- Internet access (to query upstream APIs)

**Example**:

```bash
$ .github/scripts/local-tools/test-version-detection.sh hello-world

=== Detecting version for: hello-world ===

Version source: github_releases
Calling detector: .github/scripts/detectors/github-releases.sh

✓ Version detection succeeded
Detected version: 1.0.0
```

**Troubleshooting**:
- GitHub API rate limit exceeded → Set `GITHUB_TOKEN` environment variable
- Detector script not found → Check `version_source.type` value in metadata.yaml
- Version regex mismatch → Check `version_regex` pattern (binary_version)

### check-conditional-build.sh

Checks if image would be built based on change detection logic.

```bash
.github/scripts/local-tools/check-conditional-build.sh IMAGE_NAME

# Exit codes:
# 0 = Image WOULD be built
# 1 = Image WOULD be skipped
# 2 = Missing dependencies
# 3 = Invalid arguments
```

**Checks**:
1. Git changes in Dockerfile, metadata.yaml, or data/ directory
2. Version change (detected vs. last in history.jsonl)
3. First-time build (no history file yet)

**Example: First build**

```bash
$ .github/scripts/local-tools/check-conditional-build.sh my-new-image

=== Checking: my-new-image ===

No build history found

Conclusion: Image WOULD BE BUILT
Reason: First time building (no history.jsonl)
```

**Example: No changes**

```bash
$ .github/scripts/local-tools/check-conditional-build.sh hello-world

=== Checking: hello-world ===

No git changes detected
Latest version in history: 1.0.0
Detected version: 1.0.0 (unchanged)

Conclusion: Image WOULD BE SKIPPED
Reason: No changes, version unchanged
```

### lint-dockerfile.sh

Runs hadolint on all Dockerfile(s) in an image directory.

```bash
.github/scripts/local-tools/lint-dockerfile.sh IMAGE_NAME

# Exit codes:
# 0 = All pass
# 1 = Linting errors found
# 2 = Missing dependencies (hadolint)
# 3 = Invalid arguments
# 4 = No Dockerfiles found
```

**Checks**:
- Lints `Dockerfile` (main variant)
- Lints all `Dockerfile.*` files (variants like Dockerfile.alpine)
- Uses same hadolint config as CI (`.hadolint.yaml` if present)

**Example**:

```bash
$ .github/scripts/local-tools/lint-dockerfile.sh hello-world

Linting: hello-world/Dockerfile
✓ No linting errors

Linting: hello-world/Dockerfile.alpine
✓ No linting errors

All Dockerfiles passed linting
```

## How to Add a New Version Detector

Want to detect versions from a new source type? Follow these steps:

### 1. Understand the Detector Interface

Detectors are shell scripts in `.github/scripts/detectors/` that:

- **Input**: Image directory path as argument 1
- **Output**: Detected version string to stdout
- **Exit code**: 0 on success, 1 on failure
- **Read from**: `metadata.yaml` in the image directory using `yq`

### 2. Create Detector Script

Create `.github/scripts/detectors/{source-type}.sh`:

```bash
#!/usr/bin/env bash
# Detect version from SOURCE_TYPE source
set -euo pipefail

IMAGE_DIR="$1"
METADATA_FILE="$IMAGE_DIR/metadata.yaml"

# Source configuration is in metadata.yaml under:
# version_source:
#   type: {source-type}
#   ... detector-specific fields ...

# Example for GitHub Releases:
GITHUB_REPO=$(yq eval '.version_source.repo' "$METADATA_FILE")
PRERELEASE_FILTER=$(yq eval '.version_source.prerelease_filter // false' "$METADATA_FILE")

# Call API and detect version
# ... your detection logic ...

echo "1.2.3"  # Output detected version
```

### 3. Add to Version Source Enum

Update `.github/scripts/local-tools/validate-metadata.sh`:
- Add your source type to `VALID_VERSION_SOURCES` array
- Update metadata schema documentation

### 4. Test Detector

```bash
# Test that detector script runs and outputs a version
.github/scripts/detectors/your-source.sh hello-world
```

### 5. Add Documentation

Update [docs/yaml-config-reference.md](docs/yaml-config-reference.md):
- Add section explaining source-specific fields
- Provide configuration example
- List required fields

## Architecture Decisions

When you're curious about why we made certain decisions:

- **Why native ARM64 runners?** → [ADR-0001](docs/adr/0001-native-arm64-runners.md) - 10x faster than QEMU
- **How do multi-arch builds coordinate?** → [ADR-0002](docs/adr/0002-push-by-digest.md) - Push-by-digest pattern
- **Why JSONL for history?** → [ADR-0003](docs/adr/0003-jsonl-history-format.md) - Git-friendly, append-only
- **How are detectors pluggable?** → [ADR-0004](docs/adr/0004-detector-abstraction.md) - Standard interface design
- **What if a build partially fails?** → [ADR-0005](docs/adr/0005-graceful-degradation.md) - Better than all-or-nothing

See [docs/adr/](docs/adr/) for complete Architecture Decision Records.

**When to create new ADRs**: When you're proposing major architectural changes, switching technologies, or making a decision with significant tradeoffs. Simple implementation decisions don't need ADRs.

## Code Quality Standards

### Dockerfile Quality

- **Linting**: Must pass hadolint with no errors
- **Best practices**:
  - Pin base image versions (no `latest`)
  - Group RUN commands to reduce layers
  - Use multi-stage builds when beneficial
  - Include version labels: `org.opencontainers.image.version=$VERSION`

### YAML Quality

- **Linting**: Must pass yamllint
- **Format**: 2-space indentation
- **Validation**: Must pass metadata schema validation (local script)

### Shell Script Quality (if adding scripts)

- **Linting**: Must pass shellcheck
- **Testing**: Must have BATS unit tests
- **Safety**: `set -euo pipefail` at script start
- **Error handling**: Clear error messages to stderr

## Documentation Update Requirements

When you modify workflow patterns or schema, you MUST update corresponding documentation:

| Change Type | Required Updates |
|-------------|------------------|
| New version_source | docs/yaml-config-reference.md, validate-metadata.sh |
| New metadata.yaml field | docs/yaml-config-reference.md |
| Workflow pattern change | docs/workflows.md |
| New build logic | docs/troubleshooting.md (if impacts debugging) |
| Registry configuration | docs/yaml-config-reference.md |

## Troubleshooting

### Image not building?

1. Check metadata.yaml is valid: `.github/scripts/local-tools/validate-metadata.sh IMAGE_NAME`
2. Verify version detection works: `.github/scripts/local-tools/test-version-detection.sh IMAGE_NAME`
3. Check Dockerfile lints: `.github/scripts/local-tools/lint-dockerfile.sh IMAGE_NAME`
4. See [docs/troubleshooting.md](docs/troubleshooting.md) for common issues

### Version detection fails?

- Check GitHub API rate limit: `gh api rate_limit`
- Set GitHub token: `export GITHUB_TOKEN=<your-token>`
- Verify `version_source.repo` format in metadata.yaml

### Dockerfile linting fails?

- Check .hadolint.yaml for exceptions
- Review linting rules: `hadolint --help`
- See [docs/troubleshooting.md](docs/troubleshooting.md) for common issues

## Code of Conduct

- Be respectful and constructive
- Share knowledge to help others learn
- Ask questions if something is unclear
- Report issues in a helpful way

## Getting Help

1. **Quick questions?** → Check [docs/troubleshooting.md](docs/troubleshooting.md)
2. **Configuration help?** → See [docs/yaml-config-reference.md](docs/yaml-config-reference.md)
3. **Understanding decisions?** → Read [docs/adr/](docs/adr/)
4. **Still stuck?** → Open a GitHub issue with:
   - What you're trying to do
   - What error you see
   - What you've already tried
   - Output from `validate-metadata.sh` or detector script

## Related Documentation

- [README.md](README.md) - Project overview
- [docs/yaml-config-reference.md](docs/yaml-config-reference.md) - All metadata.yaml options
- [docs/troubleshooting.md](docs/troubleshooting.md) - Common issues
- [docs/workflows.md](docs/workflows.md) - How the build system works
- [docs/adr/](docs/adr/) - Why we made key decisions
- [docs/examples/README.md](docs/examples/README.md) - Example patterns
