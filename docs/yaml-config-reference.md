# YAML Configuration Reference

Complete reference for `metadata.yaml` - the configuration file that controls how Docker images are built, versioned, and published.

## Quick Start

Minimal `metadata.yaml`:

```yaml
name: my-image
version_source: github_releases
source:
  github_repo: owner/repo
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

Method for detecting the upstream version. Determines which detector script runs.

- **Type**: String (enum)
- **Required**: Yes
- **Valid values**:
  - `github_releases` - GitHub Release tags
  - `binary_version` - Binary --version output
  - `docker_tag` - Docker registry tag
  - `http_json` - HTTP API returning JSON
- **Example**:
  ```yaml
  version_source: github_releases
  ```

#### `source`

Configuration for version detection. Structure depends on `version_source`.

- **Type**: Object (map)
- **Required**: Yes
- **Examples** (see sections below):
  ```yaml
  source:
    github_repo: owner/repo
  ```

### Conditional Fields (depends on version_source)

#### For `github_releases`:

```yaml
version_source: github_releases
source:
  github_repo: owner/repo                    # Required: GitHub repo
  version_regex: ^v(.+)$                     # Optional: extract version from tag
  prerelease_handling: prefer-stable         # Optional: stable, prefer-stable, allow-prerelease
```

- **github_repo** (string): Repository in format `owner/repo`
- **version_regex** (string): Regex pattern to extract version from release tag
  - Default: `^v(.+)$` (matches v1.2.3, extracts 1.2.3)
  - Capture group 1 extracts the version
  - Example: `^release-(.+)-final$` matches `release-1.0-final`, extracts `1.0`
- **prerelease_handling** (enum): How to handle pre-releases
  - `stable` - Skip pre-releases entirely
  - `prefer-stable` - Prefer stable, fallback to pre-release if available
  - `allow-prerelease` - Include pre-releases in version list
  - Default: `prefer-stable`

#### For `binary_version`:

```yaml
version_source: binary_version
source:
  binary_path: /usr/local/bin/myapp          # Required: path in image
  version_command: --version                 # Optional: flag to get version
  version_regex: version (.+)                # Optional: extract version from output
```

- **binary_path** (string): Path to binary inside image to execute
- **version_command** (string): Flag to pass to binary for version output
  - Default: `--version`
  - Example: `-v`, `version`, `info`
- **version_regex** (string): Regex to extract version from command output
  - Default: `(.+)` (use entire output as version)
  - Example: `v(.+)` extracts version from `v1.2.3` output

Example in Dockerfile:
```dockerfile
RUN apt-get install -y myapp
# Verify: myapp --version → "myapp version 1.2.3"
```

#### For `docker_tag`:

```yaml
version_source: docker_tag
source:
  docker_image: library/python                # Required: Docker image
  tag_pattern: "\d+\.\d+\.\d+"                # Optional: filter tags
```

- **docker_image** (string): Docker image to monitor (can be any registry)
- **tag_pattern** (string): Regex to filter which tags to consider
  - Default: Match all tags
  - Example: `\d+\.\d+\.\d+` matches semantic versions like 1.2.3

#### For `http_json`:

```yaml
version_source: http_json
source:
  url: https://api.example.com/version       # Required: HTTP endpoint
  json_path: .latest.version                 # Required: jq path to extract
  auth_header: Authorization: Bearer token   # Optional: auth header
```

- **url** (string): HTTP endpoint returning JSON
- **json_path** (string): jq path to extract version from response
  - Example: `.version` for `{"version": "1.2.3"}`
  - Example: `.releases[0].version` for nested data
- **auth_header** (string): Authentication header if API requires it
  - Format: `Header-Name: value`
  - Example: `Authorization: Bearer token123`

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

Define alternative Dockerfile variants for the same image.

- **Type**: Array of strings
- **Required**: No
- **Default**: Only main Dockerfile
- **File mapping**: Variant `alpine` maps to `Dockerfile.alpine`
- **Example**:
  ```yaml
  variants: [alpine, slim, distroless]
  ```

This requires Dockerfile files:
```
my-image/
├── Dockerfile                  # main/default variant
├── Dockerfile.alpine           # alpine variant
├── Dockerfile.slim             # slim variant
└── Dockerfile.distroless       # distroless variant
```

Each variant:
- Built independently for all architectures
- Tagged separately: `my-image:1.2.3-alpine`, `my-image:1.2.3-slim`
- Can have different base images or configurations
- Shares same version source (all variants same version)

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
version_source: github_releases
source:
  github_repo: kubernetes/kubernetes
  version_regex: ^v(.+)$
  prerelease_handling: stable
```

- Detects versions from Kubernetes GitHub releases
- Skips pre-releases (alpha, beta)
- Extracts version from tag `v1.28.0` → `1.28.0`

### Example 2: Binary Version Detection

```yaml
name: helm
version_source: binary_version
source:
  binary_path: /usr/local/bin/helm
  version_command: version --short
  version_regex: v(.+)
```

- Builds image with helm binary
- Detects version by running `helm version --short`
- Extracts version from output like `v3.12.0`

### Example 3: Docker Image Source

```yaml
name: python-base
version_source: docker_tag
source:
  docker_image: library/python
  tag_pattern: "^3\\.(1[0-9]|[0-9])$"  # Match 3.10, 3.11, 3.12, etc.
architectures: [amd64, arm64]
```

- Monitors official Python image tags
- Only considers stable versions (3.10, 3.11, etc.)
- Filters out pre-releases and RC versions

### Example 4: Multiple Variants

```yaml
name: nodejs
version_source: github_releases
source:
  github_repo: nodejs/node
  version_regex: ^v(.+)$
variants: [alpine, slim]
architectures: [amd64, arm64]
registries:
  - name: ghcr
    enabled: true
  - name: docker-hub
    enabled: true
```

- Detects version from Node.js releases
- Builds 3 variants: main, alpine, slim
- Pushes to both GHCR and Docker Hub
- Multi-arch support (amd64 and arm64)

### Example 5: Version Regex Patterns

Different projects use different tag formats:

```yaml
# Kubernetes style: v1.2.3
version_source: github_releases
source:
  github_repo: kubernetes/kubernetes
  version_regex: ^v(.+)$

# Django style: 4.2.1
version_source: github_releases
source:
  github_repo: django/django
  version_regex: ^([0-9.]+)$

# Vault style: v1.14.0+ent
version_source: github_releases
source:
  github_repo: hashicorp/vault
  version_regex: ^v(.+?)\+

# Hugo style: v0.119.0-extended
version_source: github_releases
source:
  github_repo: gohugoio/hugo
  version_regex: ^v(.+?)(?:-extended)?$
```

## Advanced: Custom Configuration

### Conditionally Skip Versions

Exclude certain version ranges with version_regex:

```yaml
# Skip release candidates
version_regex: ^(?!.*rc)v(.+)$          # negative lookahead

# Only match stable semver (not pre-releases)
version_regex: ^v(\d+\.\d+\.\d+)$       # strict semver only
```

### Multi-Regex Patterns

Some projects have inconsistent tag formats. Use fallback patterns:

```yaml
source:
  github_repo: example/repo
  version_patterns:
    - ^v(.+)$                           # Try v1.2.3
    - ^release-(.+)$                    # Fallback: release-1.2.3
    - ^(.+)$                            # Fallback: 1.2.3
```

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
- ✓ Required fields present: `name`, `version_source`, `source`
- ✓ `version_source` is one of allowed values
- ✓ Source configuration matches detector requirements
- ✓ Architecture values are valid
- ✓ Variant Dockerfiles exist
- ✓ Registry names are valid

## Troubleshooting

### Version not detecting

1. Verify version_source value is correct
2. Check source configuration matches repository/binary path
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
- `version_source` value not in allowed list
- Architecture values invalid

## Related

- [CONTRIBUTING.md](../CONTRIBUTING.md) - How to add new images
- [docs/troubleshooting.md](troubleshooting.md) - Common issues
- [docs/examples/](../docs/examples/) - Working example configurations
