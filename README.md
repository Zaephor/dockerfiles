# Docker Image Build System

Automated multi-architecture Docker image builds with intelligent change detection, version tracking, and graceful degradation.

## What is This?

This repository automates building and publishing Docker images to GHCR (GitHub Container Registry) with:

- **Automatic version detection** from upstream sources (GitHub Releases, Docker Hub, HTTP APIs)
- **Multi-architecture support** (amd64 and arm64 native builds)
- **Intelligent change detection** - only rebuild when something changes
- **Build history tracking** - complete version history for auditing and rollback
- **Graceful degradation** - if one architecture fails, publish what succeeded
- **Contributor-friendly** - add a new image with just a Dockerfile and metadata.yaml

## Quick Start

### For Users: Try an Example in 20 Minutes

Want to see how this system works? Follow one of our example templates:

1. **GitHub Releases Pattern** - Most common, detects versions from GitHub tags
   ```bash
   cp -r examples/github-release my-image
   # Edit my-image/Dockerfile, my-image/metadata.yaml
   git add my-image/
   git commit -m "Add my-image"
   git push
   ```

2. **Binary Version Detection** - For tools like `kubectl`, `helm`, etc.
   ```bash
   cp -r examples/binary-version my-tool
   ```

3. **Docker Tag Source** - Monitor another Docker image
   ```bash
   cp -r examples/docker-tag my-docker-image
   ```

See [examples/README.md](examples/README.md) for all patterns with detailed explanations.

### For Contributors: Add a New Image in 10 Minutes

1. Read [CONTRIBUTING.md](CONTRIBUTING.md) - explains exactly what files to create
2. Check [docs/yaml-config-reference.md](docs/yaml-config-reference.md) - all configuration options with examples
3. Copy an example from `examples/` matching your upstream source type
4. Test locally with scripts in `.github/scripts/local-tools/`
5. Submit pull request

## Architecture Overview

```
push to github
    ↓
lint workflow
    ↓
detect changes (which images changed?)
    ↓
matrix expansion (detect architectures for each changed image)
    ↓
parallel build jobs (amd64 and arm64 native runners)
    ↓
create multi-arch manifest
    ↓
push to GHCR
    ↓
update history.jsonl (version tracking)
```

**Key Points**:
- **Native Runners**: amd64 on `ubuntu-latest`, arm64 on `ubuntu-24.04-arm` (10x faster than QEMU)
- **Conditional Builds**: Only changed images rebuild (efficient at scale)
- **Multi-Registry**: Push to GHCR, Docker Hub, or others
- **History Tracking**: JSONL format for complete version audit trail

## Core Technologies

- **Build System**: Docker Buildx, GitHub Actions
- **Runners**: Ubuntu native (amd64 and arm64)
- **Language**: Bash 4.0+, YAML (GitHub Actions Workflow Syntax)
- **Tools**: jq (JSON), yq (YAML), hadolint (Dockerfile linting), git
- **Testing**: BATS (Bash Automated Testing System)
- **Registry**: GHCR (primary)

## Project Structure

```
.
├── README.md                           # This file (project overview)
├── CONTRIBUTING.md                     # Contributor guide
│
├── docs/                               # Detailed documentation
│   ├── workflows.md                    # Build workflow patterns
│   ├── performance.md                  # Performance metrics and optimization
│   ├── architecture-detection.md       # How multi-arch detection works
│   ├── testing.md                      # Testing and smoke test patterns
│   ├── troubleshooting.md              # Common issues and solutions
│   ├── yaml-config-reference.md        # Complete metadata.yaml schema
│   └── adr/                            # Architecture Decision Records
│       ├── 0001-native-arm64-runners.md
│       ├── 0002-push-by-digest.md
│       ├── 0003-jsonl-history-format.md
│       ├── 0004-detector-abstraction.md
│       └── 0005-graceful-degradation.md
│
├── examples/                           # Example image templates
│   ├── github-release/                 # Template: GitHub Releases
│   ├── binary-version/                 # Template: Binary --version detection
│   ├── docker-tag/                     # Template: Docker registry source
│   ├── multi-variant/                  # Template: Multiple Dockerfile variants
│   └── README.md                       # Guide to examples
│
├── .github/
│   ├── workflows/
│   │   └── build-image.yml             # Main build workflow
│   └── scripts/
│       ├── lib/                        # Shared library functions
│       ├── detectors/                  # Version detection plugins
│       ├── local-tools/                # Local testing scripts
│       │   ├── validate-metadata.sh
│       │   ├── test-version-detection.sh
│       │   ├── check-conditional-build.sh
│       │   ├── lint-dockerfile.sh
│       │   └── lib/
│       │       └── local-common.sh
│       └── [other build scripts]
│
├── tests/                              # Test suite
│   ├── unit/                           # BATS unit tests
│   └── fixtures/                       # Test data and mocks
│
└── [image-name]/                       # Image directories (example: hello-world)
    ├── Dockerfile                      # Image definition
    ├── metadata.yaml                   # Configuration and version detection
    ├── history.jsonl                   # Build history (auto-generated)
    └── data/                           # Files to COPY into image (optional)
```

## Common Tasks

### View Build Status
```bash
# Check last 5 builds
gh run list --workflow=build-image.yml --limit 5

# View detailed logs for a run
gh run view <run-id> --log
```

### Trigger Manual Build
```bash
# Rebuild specific image
gh workflow run build-image.yml -f image_filter=hello-world

# Force rebuild all images
gh workflow run build-image.yml -f force_rebuild=true

# Dry run (preview changes)
gh workflow run build-image.yml -f dry_run=true
```

### Query Build History
```bash
# See last 5 versions of an image
jq -r '.version + " (" + .timestamp + ")"' \
  hello-world/history.jsonl | tail -5

# Get performance metrics
jq -r '.architectures | to_entries | .[] | .key + ": " + (.value.duration_seconds | tostring) + "s"' \
  hello-world/history.jsonl | tail -1
```

### Test Locally Before Pushing
```bash
# Validate metadata.yaml syntax and schema
.github/scripts/local-tools/validate-metadata.sh hello-world

# Test version detection locally
.github/scripts/local-tools/test-version-detection.sh hello-world

# Check if image would be built (conditional build logic)
.github/scripts/local-tools/check-conditional-build.sh hello-world

# Lint Dockerfile(s)
.github/scripts/local-tools/lint-dockerfile.sh hello-world
```

## Key Principles

### 1. Configuration Over Convention
Add images by creating directories with Dockerfile + metadata.yaml, not code changes.

### 2. Auto-Detection First
Version and architecture detection happen automatically, with YAML overrides when needed.

### 3. Graceful Degradation
If arm64 build fails, still publish amd64 image rather than failing entirely.

### 4. Performance Optimized
Use native ARM64 runners (10x faster than QEMU) even though workflow is more complex.

### 5. Complete History
Never modify build history - append-only logs track every build for auditing.

## Architecture Decision Records

We document major architectural decisions in [docs/adr/](docs/adr/) to preserve institutional knowledge:

- **ADR-0001**: [Native ARM64 Runners](docs/adr/0001-native-arm64-runners.md) - Why we use native ARM64 runners (10x faster than QEMU)
- **ADR-0002**: [Push-by-Digest Manifest Coordination](docs/adr/0002-push-by-digest.md) - How multi-arch images coordinate across runners
- **ADR-0003**: [JSONL History Format](docs/adr/0003-jsonl-history-format.md) - Why build history is append-only JSON Lines
- **ADR-0004**: [Pluggable Version Detector Abstraction](docs/adr/0004-detector-abstraction.md) - How version detection is extensible
- **ADR-0005**: [Graceful Degradation Philosophy](docs/adr/0005-graceful-degradation.md) - Why partial success is better than total failure

See [docs/adr/](docs/adr/) directory for complete ADRs.

## Documentation Index

**For Contributors**:
- [CONTRIBUTING.md](CONTRIBUTING.md) - How to add images and run tests
- [docs/yaml-config-reference.md](docs/yaml-config-reference.md) - All configuration options explained

**For Troubleshooting**:
- [docs/troubleshooting.md](docs/troubleshooting.md) - Common issues and solutions

**For Understanding Design Decisions**:
- [docs/adr/](docs/adr/) - Architecture Decision Records explaining why we made key choices

**For Advanced Topics**:
- [docs/workflows.md](docs/workflows.md) - Deep dive into build workflow
- [docs/performance.md](docs/performance.md) - Performance metrics and optimization
- [docs/architecture-detection.md](docs/architecture-detection.md) - How multi-arch detection works

**For Examples**:
- [examples/README.md](examples/README.md) - Example templates for common patterns

## Local Development

### Prerequisites

- Bash 4.0+
- Docker 20.10+
- Git
- jq, yq, hadolint
- BATS (for testing)
- pre-commit (for code quality hooks)

### Setup Pre-commit Hooks

This project uses pre-commit hooks to enforce code quality before commits. To enable them:

```bash
# Install pre-commit (choose one)
pip install pre-commit
# OR
brew install pre-commit  # macOS
# OR
sudo apt install pre-commit  # Ubuntu/Debian

# Install the git hook scripts
pre-commit install

# (Optional) Run against all files initially
pre-commit run --all-files
```

Once installed, hooks will run automatically on `git commit`. See [docs/pre-commit-hooks.md](docs/pre-commit-hooks.md) for details on what's checked and how to use the hooks.

**What gets checked automatically:**
- GitHub Actions workflows (actionlint)
- Dockerfiles (hadolint)
- Shell scripts (shellcheck)
- YAML files (yamllint)
- Markdown documentation (markdownlint)
- Trailing whitespace, line endings, etc.

### Run Tests

```bash
# Run all unit tests
bats tests/unit/*.bats

# Run tests for local tools
bats tests/unit/local-tools.bats

# Test a specific script
bats tests/unit/local-tools.bats -f "validate-metadata"
```

## Quick Reference: Exit Codes

Local testing scripts use consistent exit codes:

| Code | Meaning | Example |
|------|---------|---------|
| 0 | Success | Validation passed |
| 1 | Validation failed | Invalid metadata or linting errors |
| 2 | Missing dependencies | Required command not found |
| 3 | Invalid arguments | Wrong arguments provided |
| 4 | File not found | Dockerfile or metadata.yaml missing |

## Common Issues & Troubleshooting

**Version detection not working?** → See [troubleshooting guide: version detection](docs/troubleshooting.md#problem-test-version-detectionsh-fails)

**Build failure in CI?** → See [troubleshooting guide: build failures](docs/troubleshooting.md#problem-docker-build-command-fails-during-build-arch-job)

**Dockerfile linting errors?** → See [troubleshooting guide: lint-dockerfile](docs/troubleshooting.md#problem-lint-dockerfilesh-reports-errors)

**Local testing script issues?** → See [troubleshooting guide: local testing scripts](docs/troubleshooting.md#local-testing-script-issues)

For comprehensive troubleshooting, see [docs/troubleshooting.md](docs/troubleshooting.md).

## Support & Contributing

Have questions? Start here:

1. **Adding images?** → Read [CONTRIBUTING.md](CONTRIBUTING.md)
2. **Configuration help?** → See [docs/yaml-config-reference.md](docs/yaml-config-reference.md)
3. **Example patterns?** → Review [examples/README.md](examples/README.md)
4. **Understanding decisions?** → Check [docs/adr/](docs/adr/)
5. **Debugging issues?** → Use [docs/troubleshooting.md](docs/troubleshooting.md)
6. **Still stuck?** → Open a GitHub issue with details and error logs

## License

See LICENSE file (if present) for details.
