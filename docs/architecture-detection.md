# Architecture Detection

Automatic architecture detection eliminates manual configuration for multi-architecture Docker builds.

## Overview

The system automatically detects which architectures (amd64, arm64) are supported by each Docker image. Detection runs during matrix generation and uses multiple detection methods in priority order.

**Detection Priority Chain**:
1. **Manual Configuration** (highest priority): Explicit `architectures` field in `metadata.yaml`
2. **Base Image Manifest**: Query Docker/OCI registry for base image platform support
3. **GitHub Release Binaries**: Scan release assets for architecture-specific binary names
4. **Download URLs**: Test architecture-specific download URLs using HTTP HEAD requests
5. **Conservative Default** (fallback): amd64 and arm64 (build both when detection fails)

## Detection Integration

### When Detection Runs

**Detection Point**: Matrix generation phase (`.github/scripts/generate-matrix.sh`)

**Workflow**:
1. Discover all image directories at project root
2. For each image requiring build (per change detection):
   - Call `detect_supported_architectures()` from architecture-detection.sh
   - Detection runs through priority chain until successful
   - Detected architectures added to matrix entry
3. Matrix JSON passed to build-arch job

**Performance**:
- Detection overhead: <30 seconds per image
- Total workflow overhead: <5% (for 10+ images)
- Cached results not used (fresh detection each run ensures accuracy)

### Matrix Entry Structure

```json
{
  "name": "hello-world",
  "version": "1.2.3",
  "reason": "version_changed",
  "architectures": ["amd64", "arm64"],
  "variant": "default",
  "dockerfile": "./hello-world/Dockerfile"
}
```

The `architectures` array controls which architectures are built in the parallel matrix.

## Detection Method 1: Manual Configuration

**Priority**: Highest (always respected when present)

### Configuration Format

Specify architecture support explicitly in `metadata.yaml`:

```yaml
# hello-world/metadata.yaml
version_source: "github_releases:library/hello-world"
architectures:
  - amd64
  - arm64
```

**Override to build only amd64**:
```yaml
architectures:
  - amd64
```

**Override to build only arm64**:
```yaml
architectures:
  - arm64
```

### Validation

The system validates manual architecture configuration:

**Valid Architecture Names**:
- `amd64` (also accepts: x86_64, x64, amd64)
- `arm64` (also accepts: aarch64, arm64, arm64v8)

**Invalid Examples**:
```yaml
architectures:
  - riscv64  # ERROR: Unsupported architecture
  - i386     # ERROR: 32-bit architectures not supported
```

**Error Handling**:
- Invalid architecture names trigger clear error messages
- Workflow fails with actionable guidance
- Empty `architectures` array treated as no manual override (proceeds to next detection method)

### When to Use Manual Configuration

**Use Cases**:
1. **Known Limitation**: Upstream only provides amd64 binaries
2. **Testing**: Temporarily disable one architecture during debugging
3. **Performance**: Skip slow architecture builds for development branches
4. **Override Detection**: Detection methods fail or are inaccurate

**Example Scenarios**:
```yaml
# Scenario 1: Upstream doesn't provide arm64 binaries yet
architectures:
  - amd64

# Scenario 2: Base image supports many architectures, but you only need two
architectures:
  - amd64
  - arm64

# Scenario 3: Development branch testing (only build fast amd64)
architectures:
  - amd64  # TODO: Re-enable arm64 before merging to main
```

## Detection Method 2: Base Image Manifest

**Priority**: Second (runs if no manual configuration)

### How It Works

Queries Docker/OCI registry for platform support using `docker buildx imagetools inspect`:

```bash
# Example: ubuntu:22.04 supports multiple architectures
docker buildx imagetools inspect --raw ubuntu:22.04 | \
  jq '.manifests[]? | select(.platform.os == "linux") | .platform.architecture'

# Output:
# amd64
# arm64
# arm (v7)
# ppc64le
# s390x

# (Filtered to supported: amd64, arm64)
```

### Base Image Extraction

The system parses Dockerfile to find the `FROM` statement:

```dockerfile
FROM ubuntu:22.04
# Detected base image: ubuntu:22.04

FROM golang:1.21-alpine AS builder
FROM alpine:3.18
# Detected base image: alpine:3.18 (final stage)
```

**Multi-Stage Handling**:
- For multi-stage builds, only the final `FROM` statement is used
- Build stages use the final runtime image's architecture support

### Manifest Types

**Multi-Arch Manifest List** (modern images):
```json
{
  "manifests": [
    {"platform": {"architecture": "amd64", "os": "linux"}},
    {"platform": {"architecture": "arm64", "os": "linux"}},
    {"platform": {"architecture": "arm", "os": "linux", "variant": "v7"}}
  ]
}
```

**Single-Arch Manifest** (legacy images):
```json
{
  "architecture": "amd64",
  "os": "linux"
}
```

Both formats are handled correctly. Legacy single-arch manifests detect only one architecture.

### Limitations

**Network Dependency**:
- Requires Docker daemon running
- Requires network access to registry
- May require authentication for private registries

**Failure Handling**:
- Network timeouts → fall back to next detection method
- Authentication failures → fall back to next detection method
- Rate limiting → fall back to next detection method

**Architecture Filtering**:
- Only Linux platforms considered (os: "linux")
- Only amd64 and arm64 extracted (other architectures ignored)
- ARM variants (v7, v8) normalized to arm64

## Detection Method 3: GitHub Release Binaries

**Priority**: Third (runs if base image detection fails)

### How It Works

Scans GitHub release assets for architecture-specific naming patterns.

**Requirements**:
- Image must use `version_source: "github_releases:owner/repo"` in metadata.yaml
- GitHub API access (uses GITHUB_TOKEN for higher rate limits)

### Asset Naming Patterns

**Detected Patterns**:
```bash
# Standard naming conventions
tool-v1.0-linux-amd64.tar.gz          → amd64
tool-v1.0-linux-arm64.tar.gz          → arm64

# Alternative architecture names (normalized)
tool-v1.0-x86_64.tar.gz               → amd64
tool-v1.0-aarch64.tar.gz              → arm64
tool-v1.0-x64.tar.gz                  → amd64

# Different file extensions
binary-amd64.zip                      → amd64
binary-arm64.deb                      → arm64
package_amd64.apk                     → amd64

# Platform-specific (filtered)
tool-v1.0-darwin-amd64.tar.gz         → (skipped - macOS)
tool-v1.0-windows-amd64.zip           → (skipped - Windows)
tool-v1.0-checksums.txt               → (skipped - no arch)
```

**Architecture Normalization**:
- `x86_64`, `x64`, `amd64` → amd64
- `aarch64`, `arm64`, `arm64v8` → arm64
- Case-insensitive matching

### API Rate Limits

**Authenticated** (with GITHUB_TOKEN):
- 5000 API calls per hour
- Recommended for all builds

**Unauthenticated**:
- 60 API calls per hour
- May cause detection failures in CI

**Rate Limit Handling**:
- If rate limit exceeded → fall back to next detection method
- Logged as warning: "GitHub API rate limit exceeded"

### Example Detection

**GitHub Release Assets**:
```json
[
  {"name": "tool-v1.2.3-linux-amd64.tar.gz", "size": 12345678},
  {"name": "tool-v1.2.3-linux-arm64.tar.gz", "size": 13456789},
  {"name": "tool-v1.2.3-darwin-amd64.tar.gz", "size": 12987654},
  {"name": "tool-v1.2.3-checksums.txt", "size": 512}
]
```

**Detection Result**:
- amd64: Found (tool-v1.2.3-linux-amd64.tar.gz)
- arm64: Found (tool-v1.2.3-linux-arm64.tar.gz)
- Architectures: ["amd64", "arm64"]

## Detection Method 4: Download URL Testing

**Priority**: Fourth (runs if GitHub release detection fails)

### How It Works

Tests architecture-specific download URLs for existence using HTTP HEAD requests.

**Requirements**:
- `download_url_template` field in metadata.yaml
- Template must include `{arch}` placeholder

### Configuration

```yaml
# hello-world/metadata.yaml
version_source: "static:1.2.3"
download_url_template: "https://example.com/v{version}/binary-{arch}.tar.gz"
```

**URLs Tested**:
```
https://example.com/v1.2.3/binary-amd64.tar.gz
https://example.com/v1.2.3/binary-arm64.tar.gz
```

### HTTP HEAD Request Testing

**Method**:
```bash
# Test if URL exists without downloading
curl -I --fail --silent --max-time 10 \
  "https://example.com/v1.2.3/binary-amd64.tar.gz"

# Exit code 0 (success) → Architecture available
# Exit code non-zero (404, timeout) → Architecture not available
```

**Features**:
- Uses HTTP HEAD requests (no full download)
- 10-second timeout per URL
- Fallback to range GET for CDNs that block HEAD
- <2 seconds per URL test (total <4 seconds per image)

**CDN Compatibility**:
Some CDNs block HEAD requests. The system automatically falls back to range GET:
```bash
curl --fail --silent --max-time 10 --range 0-0 \
  "https://example.com/v1.2.3/binary-amd64.tar.gz"
```

### Example Detection

**Template**:
```yaml
download_url_template: "https://cdn.example.com/releases/{version}/app-linux-{arch}.tar.gz"
version: "2.5.0"
```

**URL Tests**:
```
Test 1: https://cdn.example.com/releases/2.5.0/app-linux-amd64.tar.gz → 200 OK
Test 2: https://cdn.example.com/releases/2.5.0/app-linux-arm64.tar.gz → 404 Not Found
```

**Detection Result**:
- amd64: Available (200 OK)
- arm64: Not available (404)
- Architectures: ["amd64"]

## Detection Method 5: Conservative Default

**Priority**: Lowest (fallback when all detection methods fail)

### When Used

Conservative default is used when:
- No manual configuration provided
- Base image manifest query fails (network error, auth error)
- No GitHub releases available or release detection fails
- No download URL template provided or URL tests fail

### Default Behavior

**Architectures**: ["amd64", "arm64"]

**Philosophy**: Build both architectures and let graceful degradation handle failures.

**Rationale**:
1. Most modern base images support both amd64 and arm64
2. If one architecture fails at build time, the other still publishes (graceful degradation)
3. Better to attempt both than to skip one prematurely
4. Workflow succeeds with partial availability (single-arch manifest)

### Logging

When conservative default is used, the system logs:
```
[WARN] Architecture detection failed for hello-world, using conservative default: amd64 arm64
[INFO] Detection failure reason: Base image manifest not found, no GitHub releases
```

## Graceful Degradation

### Detection Failure

When detection fails or is unavailable:
1. Falls back to conservative default (amd64 + arm64)
2. Both architectures included in build matrix
3. Build failures handled by existing Sprint 8a logic
4. Workflow succeeds with available architectures only

### Build Failure

When one architecture fails at build time:
1. Single-arch manifest created for successful architecture
2. Workflow succeeds (not failure)
3. Logs show why architecture was excluded

**Example Scenarios**:
- Detection says both architectures available, but arm64 binaries actually missing → amd64-only manifest published
- Detection falls back to default, arm64 build fails → amd64-only manifest published
- Detection correctly identifies amd64-only, only amd64 built → amd64-only manifest published

## Architecture Detection Library

Library: `.github/scripts/lib/architecture-detection.sh`

### Main Function

**detect_supported_architectures**:
```bash
detect_supported_architectures <image_directory>
# Returns: Space-separated list of architectures (e.g., "amd64 arm64")
# Runs through priority chain until successful detection
```

**Example Usage**:
```bash
#!/bin/bash
source .github/scripts/lib/architecture-detection.sh

image_dir="./hello-world"
architectures=$(detect_supported_architectures "$image_dir")
echo "Detected architectures: $architectures"
# Output: Detected architectures: amd64 arm64
```

### Helper Functions

**get_manual_architectures**:
```bash
get_manual_architectures <image_directory>
# Reads architectures from metadata.yaml
# Returns: Space-separated list or empty string if not configured
```

**detect_from_base_image**:
```bash
detect_from_base_image <image_directory>
# Queries Docker registry for base image platforms
# Returns: Space-separated list or empty string on failure
```

**detect_from_github_releases**:
```bash
detect_from_github_releases <owner> <repo> <version>
# Scans GitHub release assets for architecture patterns
# Returns: Space-separated list or empty string on failure
```

**detect_from_download_urls**:
```bash
detect_from_download_urls <url_template> <version>
# Tests architecture-specific URLs for existence
# Returns: Space-separated list or empty string on failure
```

**normalize_architecture**:
```bash
normalize_architecture <arch_name>
# Normalizes architecture name variants
# Examples: x86_64 → amd64, aarch64 → arm64
# Returns: Normalized name or original if no normalization needed
```

## Architecture Detection Logging

Logs show detection decision chain and rationale for debugging.

### Log Format

```
[DEBUG] Detecting supported architectures for: ./hello-world
[DEBUG] No manual architecture configuration found in metadata.yaml
[DEBUG] Querying manifest for base image: ubuntu:22.04
[DEBUG] Base image manifest query successful
[INFO] Detected architectures from base image: amd64 arm64
Matrix Decision: [INCLUDE] Image: hello-world, Version: 1.2.3, Architectures: amd64 arm64
```

### Logging Levels

**DEBUG**:
- Detection method details
- Querying manifests/APIs
- URL testing results
- Normalization operations

**INFO**:
- Detection results (which method succeeded)
- Final architecture list

**WARN**:
- Detection failures with fallback to next method
- Rate limit warnings
- Network errors (non-fatal)

**ERROR**:
- Invalid configuration (unsupported architecture names)
- Critical failures requiring workflow abort

### Example Logs

**Successful Detection (Base Image)**:
```
[DEBUG] Detecting supported architectures for: ./myapp
[DEBUG] Querying manifest for base image: golang:1.21-alpine
[DEBUG] Found multi-arch manifest with platforms: amd64, arm64, arm, ppc64le, s390x
[INFO] Filtered to supported architectures: amd64 arm64
```

**Fallback to Conservative Default**:
```
[WARN] Base image manifest query failed: Network timeout
[DEBUG] Checking for GitHub releases: owner/repo
[WARN] GitHub release detection failed: No release found for version 1.2.3
[WARN] No download_url_template in metadata.yaml
[WARN] All detection methods failed, using conservative default
[INFO] Conservative default architectures: amd64 arm64
```

**Manual Override**:
```
[DEBUG] Detecting supported architectures for: ./custom-app
[INFO] Manual architecture configuration found: amd64
[INFO] Skipping auto-detection (manual override takes precedence)
```

## Testing Architecture Detection

### Unit Tests

Test all detection methods and normalization:

```bash
# Run architecture detection tests
bats tests/unit/architecture-detection.bats

# Test coverage:
# - Architecture normalization (34 tests)
# - Configuration validation
# - Detection methods (base image, releases, URLs, manual)
# - Graceful degradation (fallback to default)
```

**Expected Test Results**:
- All 34 tests pass
- Normalization handles all common architecture name variants
- Invalid architecture names properly rejected
- Conservative default used when all methods fail

### Integration Test

Test with real image (ubuntu:22.04):

```bash
# Test base image detection with multi-arch image
image_dir="./hello-world"
detected=$(source .github/scripts/lib/architecture-detection.sh && \
           detect_supported_architectures "$image_dir")
echo "Detected: $detected"
# Expected output: amd64 arm64
```

### Test Fixtures

Located in `tests/fixtures/`:

**manifests/multi-arch.json**:
- Multi-arch manifest list (ubuntu style)
- Contains amd64, arm64, arm, ppc64le, s390x platforms
- Used to test manifest parsing

**manifests/single-arch.json**:
- Single-arch manifest (legacy format)
- Contains only amd64 platform
- Used to test backwards compatibility

**release-assets/standard.json**:
- GitHub release assets with architecture names
- Contains linux-amd64, linux-arm64, darwin-amd64 binaries
- Used to test release asset detection

### Manual Testing

**Test detection for specific image**:
```bash
# Test hello-world image
cd hello-world
detected=$(source ../.github/scripts/lib/architecture-detection.sh && \
           detect_supported_architectures .)
echo "Detected architectures: $detected"
```

**Test with debug logging**:
```bash
# Enable debug logging
export DEBUG=1
detected=$(source .github/scripts/lib/architecture-detection.sh && \
           detect_supported_architectures ./hello-world)
# Expected: Detailed logs showing detection chain
```

**Test manual configuration override**:
```bash
# Add manual config to metadata.yaml
echo "architectures:" >> hello-world/metadata.yaml
echo "  - amd64" >> hello-world/metadata.yaml

# Test detection (should use manual config)
detected=$(source .github/scripts/lib/architecture-detection.sh && \
           detect_supported_architectures ./hello-world)
echo "$detected"  # Expected: amd64 (only)
```

## Validation Checklist

After implementation, verify:

- [ ] Auto-detection works for multi-arch base images (ubuntu:22.04)
- [ ] GitHub release binary detection identifies amd64 and arm64 binaries
- [ ] Download URL testing finds architecture-specific binaries
- [ ] Manual override in metadata.yaml takes precedence over detection
- [ ] Invalid architecture names trigger helpful error messages
- [ ] Detection failures gracefully fall back to conservative default
- [ ] Matrix generation includes detected architectures for each image
- [ ] Single-arch manifests created when one architecture unavailable
- [ ] Workflow succeeds with partial availability (not failure)
- [ ] Detection overhead <5% of total build time (<30 seconds per image)
- [ ] All unit tests pass (34 tests in architecture-detection.bats)
- [ ] Constitution compliance: Principle 1 (auto-detection), Principle 2 (graceful degradation)

## Troubleshooting

**Detection always falls back to default**:
- Check Docker daemon is running (base image detection requires Docker)
- Verify network connectivity to registries and GitHub API
- Check GITHUB_TOKEN is available (for higher API rate limits)
- Enable debug logging: `export DEBUG=1`

**Base image detection fails**:
- Verify base image exists and is accessible
- Check Docker authentication for private registries
- Test manually: `docker buildx imagetools inspect --raw <base-image>`

**GitHub release detection fails**:
- Verify version_source is correct: `github_releases:owner/repo`
- Check release exists for the version being built
- Verify GITHUB_TOKEN has `repo` or `public_repo` scope
- Check rate limits: `curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/rate_limit`

**Download URL testing fails**:
- Verify download_url_template includes {version} and {arch} placeholders
- Test URLs manually: `curl -I <url>`
- Check CDN supports HEAD requests (or uses range GET fallback)
- Verify URLs are publicly accessible (no authentication required)

**Manual configuration not respected**:
- Check architectures field is in correct YAML format (list with dashes)
- Verify metadata.yaml is valid YAML (no syntax errors)
- Check spelling: `architectures` not `architecture`
- Ensure values are valid: amd64 or arm64 only

## Summary

Architecture detection provides:
- **Automatic Detection**: No manual configuration required for most images
- **Multiple Detection Methods**: Base image, GitHub releases, download URLs
- **Manual Override**: Explicit control when needed
- **Conservative Fallback**: Build both architectures when detection uncertain
- **Graceful Degradation**: Partial success acceptable (single-arch manifests)
- **Observable**: Detailed logging shows detection decision chain

**Key Principles**:
1. Prefer automatic detection over manual configuration
2. Manual configuration always takes precedence when provided
3. Use conservative default when all detection methods fail
4. Build failures handled at build time, not detection time
5. Detection overhead must remain <5% of workflow time
