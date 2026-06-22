# YAML Configuration Reference

Complete reference for `metadata.yaml` - the configuration file that controls how Docker images are built, versioned, and published.

## Quick Start

Minimal `metadata.yaml`:

```yaml
name: my-image
version_source:
  type: github_releases
  repo: owner/repo
```

This enables:
- Automatic version detection from GitHub Releases
- Multi-architecture builds (amd64, arm64)
- Auto-detection of supported architectures
- Build history tracking

## Field Reference

### Required Fields

#### `name`

Image name used for tagging. Must be lowercase alphanumeric with hyphens.

- **Type**: String
- **Required**: Yes
- **Pattern**: `^[a-z0-9]+(-[a-z0-9]+)*$`
- **Example**:
  ```yaml
  name: hello-world
  name: my-app
  name: kubernetes-tools
  ```

#### `version_source`

How to detect the upstream version. This is a **map** carrying a `type` plus the
fields that detector needs. The `type` value must match a detector script name
(`.github/scripts/detectors/<type>.sh`). There is no separate `source:` block —
the detector's fields live directly under `version_source`.

- **Type**: Object (map), or a sequence of such maps for a fallback chain
- **Required**: Yes
- **`type`** (string, required): one of
  - `github_releases` - GitHub Release tags
  - `git_commit` - latest commit SHA on a branch
  - `docker_tag` - newest matching tag in a Docker registry
  - `docker_digest` - manifest digest of a fixed Docker tag
  - `binary_version` - version printed by a binary inside the image
  - `http_json` - version field from an HTTP JSON/XML endpoint
- **Example**:
  ```yaml
  version_source:
    type: github_releases
    repo: owner/repo
  ```

**Fallback chain** — list several detectors; the first that succeeds wins:

```yaml
version_source:
  - type: github_releases
    repo: owner/repo
  - type: binary_version
    binary_path: /usr/local/bin/tool
    version_regex: '([0-9.]+)'
```

### Detector fields (per `type`)

> Regex fields are matched with bash `[[ =~ ]]` (POSIX ERE). Use `[0-9]`, not `\d`.

#### `github_releases`

```yaml
version_source:
  type: github_releases
  repo: owner/repo                  # Required: GitHub repo (owner/name)
  # prerelease_filter: false        # Optional: include pre-releases (default: false)
  # auth_token_secret: GITHUB_TOKEN # Optional: env var holding a GitHub token
```

- **repo** (string, required): repository in `owner/name` form. The latest non-draft,
  non-prerelease release tag is used (leading `v` is stripped).

#### `git_commit`

```yaml
version_source:
  type: git_commit
  repo: owner/repo                  # Required: GitHub repo (owner/name)
  branch: main                      # Optional: branch (default: repo's default branch)
  # auth_token_secret: GITHUB_TOKEN # Optional
```

- **repo** (string, required): repository to read commits from.
- **branch** (string, optional): branch to track; the short commit SHA becomes the version.

#### `docker_tag`

```yaml
version_source:
  type: docker_tag
  registry: docker.io               # Required: registry host
  image: library/python             # Required: image name (no registry prefix)
  # tag_filter: '^[0-9]+\.[0-9]+$'  # Optional: regex selecting version tags
  # auth_token_secret: GHCR_TOKEN   # Optional
```

- **registry** / **image** (string, required): which registry image to watch.
- **tag_filter** (string, optional): ERE selecting which tags count; the highest
  matching version is chosen.

#### `docker_digest`

```yaml
version_source:
  type: docker_digest
  registry: docker.io               # Required: registry host
  image: library/alpine             # Required: image name (no registry prefix)
  tag: "3.19"                       # Required: tag to track (may contain {variant})
  # auth_token_secret: GITHUB_TOKEN # Optional
```

- Tracks the manifest **digest** of a fixed tag; rebuilds when the upstream tag is
  re-pushed. `tag` may contain `{variant}` for per-variant tracking.

#### `binary_version`

```yaml
version_source:
  type: binary_version
  binary_path: /usr/local/bin/myapp   # Required: path in the built image
  version_regex: 'myapp ([0-9.]+)'    # Required: ERE; capture group 1 is the version
  # version_flags: --version          # Optional: flags passed to the binary (default: --version)
```

- Builds the image, runs `binary_path version_flags`, and extracts capture group 1
  of `version_regex` from the combined stdout/stderr.

#### `http_json`

```yaml
version_source:
  type: http_json
  url: https://api.example.com/version  # Required: endpoint
  format: json                          # Required: json or xml
  path: .latest.version                 # Required: jq path (json) / XPath (xml)
  # headers:                            # Optional: request headers (${VAR} expanded)
  #   Authorization: 'Bearer ${API_TOKEN}'
```

- **url** / **format** / **path** (required): fetch the endpoint and extract the version.
  - `path: .version` for `{"version": "1.2.3"}`; `.releases[0].version` for nested data.

### Optional Fields

#### `architectures`

Override auto-detected architecture support. Auto-detection queries base image manifest by default.

- **Type**: Array of strings
- **Required**: No
- **Default**: Auto-detect (usually amd64, arm64)
- **Valid values**: amd64, arm64, 386, ppc64le, s390x
- **Example**:
  ```yaml
  architectures: [amd64, arm64]              # Explicit support
  architectures: [amd64]                     # Single architecture
  ```

When to override:
- Base image claims support for multiple architectures but upstream binary only has amd64
- Binary is available for additional architectures beyond what base image advertises
- Testing single-architecture builds for validation

#### `variants`

Define and control which Dockerfile variants are built for an image.

- **Type**: Array of strings
- **Required**: No
- **Default**: All discovered `Dockerfile.*` files
- **File mapping**: Variant `alpine` maps to `Dockerfile.alpine`
- **Filtering**: When specified, only listed variants will be built
- **Example**:
  ```yaml
  variants: [alpine, slim, distroless]
  ```

This requires Dockerfile files:
```
my-image/
├── Dockerfile                  # main/default variant (always included)
├── Dockerfile.alpine           # alpine variant
├── Dockerfile.slim             # slim variant
└── Dockerfile.distroless       # distroless variant
```

##### Variant Filtering Behavior

**When `variants` field is omitted or empty:**
- System discovers all `Dockerfile.*` files in the image directory
- All discovered variants are built
- Useful during development or when all variants should always build

**When `variants` field is specified:**
- Only listed variants are built
- Discovered `Dockerfile.*` files not in the list are excluded with a warning
- The default variant (`Dockerfile`) is always included, regardless of this list
- Prevents accidental builds of old or test Dockerfiles

**Example**: Enforceable filtering
```yaml
# Directory contains: Dockerfile.act-22.04, Dockerfile.act-24.04, Dockerfile.act-20.04
variants:
  - act-22.04
  - act-24.04
# Result: Only act-22.04 and act-24.04 are built
# Warning: "Excluded variants: act-20.04"
```

##### Variant Properties

Each variant:
- Built independently for all architectures
- Tagged separately: `my-image:1.2.3-alpine`, `my-image:1.2.3-slim`
- Can have different base images or configurations
- Shares same version source (all variants use same detected version)

#### `tags`

Control Docker image tag generation with custom patterns and strategies.

- **Type**: Object
- **Required**: No
- **Default**: Standard tagging (version, variant, latest)
- **Example**:
  ```yaml
  tags:
    strategy: variant_only
    patterns:
      - "{variant}-{date}"
      - "{variant}-{version}"
  ```

##### Tag Strategy

Controls which tags are automatically generated for variants.

- **Type**: String (enum)
- **Required**: No
- **Default**: `default` (all variant tags)
- **Valid values**:
  - `default` - Generate all variant tags (version-variant, variant, latest-variant)
  - `variant_only` - Only generate clean variant name tag (prevents confusing tags like "latest-variant")
- **Example**:
  ```yaml
  tags:
    strategy: variant_only
  ```

When `variant_only` is used:
- Default variant gets: `latest`, `{version}`, `{commit}`
- Named variants get: `{variant}`, `{commit}`, and custom patterns
- Prevents tags like `latest-act-24.04` or `{version}-act-24.04`
- Each variant tag acts as "latest" for that specific variant

##### Custom Tag Patterns

Define custom tag patterns using template variables.

- **Type**: Array of strings
- **Required**: No
- **Default**: No custom patterns
- **Template Variables**:
  - `{variant}` - Variant name (e.g., `alpine`, `act-24.04`)
  - `{version}` - Detected version (e.g., `1.2.3`)
  - `{date}` - Build date in YYYYMMDD format (e.g., `20251116`)
  - `{sha}` - Short upstream digest (first 12 chars of SHA256, e.g., `0154a41a7030`)
  - `{arch}` - Architecture (e.g., `amd64`, `arm64`) - only for arch-specific tags
- **Example**:
  ```yaml
  tags:
    patterns:
      - "{variant}-{date}"              # act-24.04-20251116
      - "{variant}-{sha}"               # act-24.04-0154a41a7030
      - "{variant}-{version}"           # act-24.04-1.2.3
      - "{version}-{variant}-{date}"    # 1.2.3-alpine-20251116
  ```

Custom patterns are useful for:
- **Date-based rollback**: Pin to specific build date (`act-24.04-20251116`)
- **SHA-based pinning**: Pin to exact upstream digest (`act-24.04-0154a41a7030`)
- **Hybrid tags**: Combine version and variant (`1.2.3-alpine`)
- **Tracking versions**: Track upstream version changes per variant

Pattern resolution:
- Variables are replaced with actual values during manifest creation
- If a required variable is missing, the pattern is skipped
- Patterns are added in addition to standard tags (commit, branch)

##### Complete Tags Example

```yaml
name: catthehacker-ubuntu-dind
variants: [act-22.04, act-24.04]

tags:
  strategy: variant_only
  patterns:
    - "{variant}-{date}"
    - "{variant}-{sha}"

# This generates tags:
# - ghcr.io/user/repo/image:{commit}            (all variants)
# - ghcr.io/user/repo/image:{branch}            (all variants)
# - ghcr.io/user/repo/image:act-24.04           (variant tag)
# - ghcr.io/user/repo/image:act-24.04-20251116  (date pattern)
# - ghcr.io/user/repo/image:act-24.04-0154a41a7030  (sha pattern)
# - ghcr.io/user/repo/image:act-22.04           (variant tag)
# - ghcr.io/user/repo/image:act-22.04-20251116  (date pattern)
# - ghcr.io/user/repo/image:act-22.04-abc123def456  (sha pattern)
```

#### `registries`

Push to multiple registries. GHCR is always primary.

- **Type**: Array of objects
- **Required**: No
- **Default**: GHCR only
- **Example**:
  ```yaml
  registries:
    - name: docker-hub
      enabled: true
    - name: quay
      enabled: false                         # skip this registry
  ```

Supported registries:
- `ghcr` - GitHub Container Registry (always included, primary)
- `docker-hub` - Docker Hub
- `quay` - Quay.io
- Others as configured in CI

Each registry:
- Gets same image with repository-specific naming
- Push failures don't block other registries
- Requires authentication credentials in GitHub Secrets

#### `build_options`

Control build behavior and optimization.

- **Type**: Object
- **Required**: No
- **Example**:
  ```yaml
  build_options:
    cache: true                                # Use build cache
    layer_optimization: true                  # Multi-stage optimization
  ```

Available options:
- `cache` (boolean): Enable BuildKit cache (default: true)
- `layer_optimization` (boolean): Suggest multi-stage builds (default: true)

#### `labels`

Custom OCI labels applied to image.

- **Type**: Object (key-value pairs)
- **Required**: No
- **Example**:
  ```yaml
  labels:
    org.opencontainers.image.title: My App
    org.opencontainers.image.description: Description of my app
    org.opencontainers.image.vendor: Vendor Name
  ```

Automatically added labels (don't specify these):
- `org.opencontainers.image.version` - Detected version
- `org.opencontainers.image.created` - Build timestamp
- `org.opencontainers.image.revision` - Git commit SHA
- `org.opencontainers.image.source` - Repository URL

## Complete Examples

### Example 1: GitHub Releases (Most Common)

```yaml
name: kubectl
version_source:
  type: github_releases
  repo: kubernetes/kubernetes
```

- Detects versions from Kubernetes GitHub releases
- Skips drafts and pre-releases; strips a leading `v` (tag `v1.28.0` → `1.28.0`)

### Example 2: Binary Version Detection

```yaml
name: helm
version_source:
  type: binary_version
  binary_path: /usr/local/bin/helm
  version_flags: version --short
  version_regex: 'v([0-9.]+)'
```

- Builds image with helm binary
- Detects version by running `helm version --short`
- Extracts capture group 1 from output like `v3.12.0` → `3.12.0`

### Example 3: Docker Tag Source

```yaml
name: python-base
version_source:
  type: docker_tag
  registry: docker.io
  image: library/python
  tag_filter: '^3\.(1[0-9]|[0-9])$'   # Match 3.10, 3.11, 3.12, etc.
architectures: [amd64, arm64]
```

- Monitors official Python image tags
- `tag_filter` keeps only stable minor versions; the highest match wins

### Example 4: Docker Digest Source

```yaml
name: my-base
version_source:
  type: docker_digest
  registry: docker.io
  image: library/alpine
  tag: "3.19"
architectures: [amd64, arm64]
```

- Tracks the digest of `alpine:3.19`; rebuilds whenever that tag is re-pushed upstream

### Example 5: Multiple Variants

```yaml
name: nodejs
version_source:
  type: github_releases
  repo: nodejs/node
variants: [alpine, slim]
architectures: [amd64, arm64]
```

- Detects version from Node.js releases
- Builds 3 variants: default, alpine, slim — all sharing the detected version
- Multi-arch support (amd64 and arm64)

## Validation

Metadata is validated before each build:

```bash
# Validate locally
.github/scripts/local-tools/validate-metadata.sh IMAGE_NAME

# In CI
# Workflow automatically validates all modified metadata.yaml files
```

Validation checks:
- ✓ YAML syntax is valid
- ✓ Required fields present: `name`, `version_source`
- ✓ `version_source` is a map whose `type` is one of the allowed values
- ✓ The detector's required fields are present for that `type`
- ✓ Architecture values are valid
- ✓ Variant Dockerfiles exist

## Troubleshooting

### Version not detecting

1. Verify `version_source.type` is correct
2. Check the detector's fields match the repository/binary path
3. Test locally: `.github/scripts/local-tools/test-version-detection.sh IMAGE_NAME`
4. Check GitHub API rate limits: `gh api rate_limit`
5. See [docs/troubleshooting.md](troubleshooting.md)

### Wrong version detected

- Check `version_regex` pattern matches your tag format
- Test regex: `git tag | grep -E 'YOUR_REGEX_HERE'`
- Use `.github/scripts/local-tools/test-version-detection.sh` to debug

### Metadata validation fails

Run validation locally to see detailed errors:

```bash
.github/scripts/local-tools/validate-metadata.sh IMAGE_NAME
```

Common issues:
- YAML indentation (must be 2 spaces)
- Required fields missing
- `version_source.type` not in allowed list
- Architecture values invalid

## Related

- [CONTRIBUTING.md](../CONTRIBUTING.md) - How to add new images
- [docs/troubleshooting.md](troubleshooting.md) - Common issues
- [docs/examples/](../docs/examples/) - Working example configurations
