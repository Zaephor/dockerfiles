# Example Image Templates

This directory contains ready-to-use example templates for common patterns. Copy any example and customize it for your needs.

## Quick Pattern Finder

| What You Want | Example | Copy Command |
|--------------|---------|--------------|
| GitHub Releases (most common) | [github-release/](github-release/) | `cp -r examples/github-release my-image` |
| Binary --version output | [binary-version/](binary-version/) | `cp -r examples/binary-version my-tool` |
| Monitor Docker image tags | [docker-tag/](docker-tag/) | `cp -r examples/docker-tag my-app` |
| Multiple variants (alpine, slim) | [multi-variant/](multi-variant/) | `cp -r examples/multi-variant my-app` |

## Getting Started (5 Minutes)

1. **Choose a pattern** from the table above that matches your upstream source
2. **Copy the example**:
   ```bash
   cp -r examples/github-release my-new-image
   ```
3. **Customize** the Dockerfile and metadata.yaml:
   - Update `name` in metadata.yaml
   - Update `version_source` and `source` fields
   - Update download URL or base image
4. **Test locally**:
   ```bash
   .github/scripts/local-tools/validate-metadata.sh my-new-image
   .github/scripts/local-tools/test-version-detection.sh my-new-image
   ```
5. **Commit and push**:
   ```bash
   git add my-new-image/
   git commit -m "Add my-new-image"
   git push
   ```

## Patterns

### 1. GitHub Releases Pattern

**Files**: [github-release/](github-release/)
**Use When**: Upstream publishes releases on GitHub with binary assets
**Examples**: kubectl, helm, prometheus, docker, git-lfs, etc.

```yaml
version_source: github_releases
source:
  github_repo: owner/repo
  version_regex: ^v(.+)$
  prerelease_handling: stable
```

**How it works**:
1. Queries GitHub API for latest release
2. Extracts version from tag with regex
3. Downloads binary from release assets
4. Builds image with downloaded binary

**Dockerfile**:
```dockerfile
RUN curl -fsSL "https://github.com/owner/repo/releases/download/v${VERSION}/binary-linux-amd64.tar.gz" | \
    tar xzf - -C /usr/local/bin/
```

### 2. Binary Version Pattern

**Files**: [binary-version/](binary-version/)
**Use When**: Tool prints version from `tool --version` command
**Examples**: go, rust, deno, bun, etc.

```yaml
version_source: binary_version
source:
  binary_path: /usr/local/bin/tool
  version_command: --version
  version_regex: "version (.+)"
```

**How it works**:
1. Builds image (with tool installed)
2. Runs `tool --version` inside image
3. Extracts version with regex
4. Tags image with detected version

**Dockerfile**:
```dockerfile
RUN apt-get install -y tool
# Then CI runs: tool --version → extracts version
```

**When to use**:
- Official package repositories (apt, brew, yum) already have tool
- Tool binaries are available from well-known sources
- Version is accurately reflected in `--version` output

### 3. Docker Tag Source Pattern

**Files**: [docker-tag/](docker-tag/)
**Use When**: Base image you depend on gets new versions
**Examples**: python, node, golang, ubuntu, debian, etc.

```yaml
version_source: docker_tag
source:
  docker_image: library/python
  tag_pattern: "^3\\.(1[0-9]|[0-9])$"
```

**How it works**:
1. Monitors specified Docker image registry
2. Filters tags with regex pattern
3. Uses latest matching tag as version
4. Rebuilds image when new tag appears

**When to use**:
- You build on top of official images
- Want to track base image updates
- Image is maintained in official Docker Hub or similar

### 4. Multi-Variant Pattern

**Files**: [multi-variant/](multi-variant/)
**Use When**: You want to provide multiple base image options
**Examples**: app with debian and alpine variants

```yaml
variants: [alpine]          # or [alpine, slim, distroless]
version_source: github_releases
source:
  github_repo: owner/repo
```

**How it works**:
1. Main `Dockerfile` (default variant)
2. `Dockerfile.alpine`, `Dockerfile.slim`, etc.
3. Each variant builds independently
4. Creates separate tags: `app:1.2.3`, `app:1.2.3-alpine`, `app:1.2.3-slim`

**File structure**:
```
my-app/
├── Dockerfile               # Main variant
├── Dockerfile.alpine        # Alpine variant
├── Dockerfile.slim          # Slim variant (optional)
└── metadata.yaml            # All share same version
```

**When to use**:
- Users need different size/feature tradeoffs
- Alpine for minimal deployments, Debian for compatibility
- Example: Python 3.11-slim vs 3.11-full

## Pattern Selection Guide

### By Upstream Source Type

**Official GitHub Repository with Releases**
→ Use GitHub Releases pattern

**Tool/Language from Standard Package Manager**
→ Use Binary Version pattern

**Base Image You Depend On**
→ Use Docker Tag Source pattern

**Application Needing Multiple Variants**
→ Use Multi-Variant pattern + one of the above

### By Project Maturity

**Mature Project (Kubernetes, Go, Rust)**
→ Usually GitHub Releases (most common)

**Emerging Tool**
→ Binary Version or Docker Tag Source

**Language Runtime (Python, Node, Go)**
→ Docker Tag Source

## Real-World Comparison

### Example 1: kubectl

- **Pattern**: GitHub Releases
- **Upstream**: kubernetes/kubernetes
- **Version Detection**: GitHub API releases
- **Binary**: Attached to releases
- **Configuration**:
  ```yaml
  version_source: github_releases
  source:
    github_repo: kubernetes/kubernetes
    version_regex: ^v(.+)$
  ```

### Example 2: Python-based App

- **Pattern**: Docker Tag Source
- **Upstream**: library/python
- **Version Detection**: Docker registry tags
- **Binary**: Base image
- **Configuration**:
  ```yaml
  version_source: docker_tag
  source:
    docker_image: library/python
    tag_pattern: "^3\\.(1[0-9]|[0-9])(?:-slim)?$"
  ```

### Example 3: Compiled Tool with Binary Release

- **Pattern**: GitHub Releases
- **Upstream**: owner/tool-repo
- **Version Detection**: GitHub releases
- **Binary**: Released tarball with pre-compiled binary
- **Configuration**:
  ```yaml
  version_source: github_releases
  source:
    github_repo: owner/tool-repo
    version_regex: ^v(.+)$
  ```

## Complete Checklist for New Image

- [ ] Copy example matching your upstream source type
- [ ] Update image name in metadata.yaml
- [ ] Update version source and source config
- [ ] Update Dockerfile (base image, installation steps)
- [ ] Test locally: `validate-metadata.sh`
- [ ] Test locally: `test-version-detection.sh`
- [ ] Test locally: `lint-dockerfile.sh`
- [ ] Commit with descriptive message
- [ ] Push to create pull request (or push directly if you have write access)

## Troubleshooting

**Metadata validation fails**
```bash
.github/scripts/local-tools/validate-metadata.sh my-image
```
Check YAML syntax and required fields.

**Version detection fails**
```bash
.github/scripts/local-tools/test-version-detection.sh my-image
export GITHUB_TOKEN=your_token   # If GitHub API rate limit
```
Verify `github_repo` or detector configuration.

**Dockerfile linting fails**
```bash
.github/scripts/local-tools/lint-dockerfile.sh my-image
```
Fix hadolint warnings/errors.

## Next Steps

1. **After copying example**: See that example's `README.md` for pattern details
2. **Configuration help**: See [docs/yaml-config-reference.md](../docs/yaml-config-reference.md)
3. **Adding detectors**: See [CONTRIBUTING.md](../CONTRIBUTING.md) "How to Add Version Detector"
4. **Stuck?**: Check [docs/troubleshooting.md](../docs/troubleshooting.md)

## Contributing New Examples

Have a pattern we should document? Consider submitting a new example:

1. Create directory in `examples/{pattern-name}`
2. Add minimal working Dockerfile and metadata.yaml
3. Add detailed README explaining pattern
4. Submit pull request

Your example will help other contributors!
