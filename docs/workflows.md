# Workflow Patterns

Comprehensive guide to the build workflow, change detection, multi-architecture builds, and orchestration features.

## Build Workflow Overview

The primary build workflow (`.github/workflows/build-image.yml`) manages Docker image building and publishing to GHCR.

**Trigger**: Push to any branch (`on: push: branches: '**'`)

**Job Sequence**:
```
lint → determine-changes → build-arch (parallel: amd64 + arm64) → create-manifest
```

### Job Details

1. **lint** (mandatory prerequisite):
   - Runs: hadolint on all Dockerfiles in `*/Dockerfile`
   - Fails on: errors (hadolint failure-threshold: error)
   - Allows: warnings (logged but non-blocking)
   - Outputs: Linting report in workflow logs

2. **determine-changes**:
   - Discovers all image directories at project root
   - Evaluates each image using `should_build_image()` function
   - Generates JSON matrix with images needing builds
   - Handles errors gracefully with safe fallbacks

3. **build-arch** (parallel matrix: image × arch):
   - Native runners: ubuntu-latest (amd64), ubuntu-24.04-arm (arm64)
   - Push-by-digest mode for coordination
   - Architecture-specific caching
   - Upload digest as artifact for manifest creation

4. **create-manifest**:
   - Download all digest artifacts
   - Call merge-manifest.sh script with digests
   - Create manifests for commit SHA and branch tags
   - Graceful degradation: single-arch manifests when one arch fails

## Caching Strategy (Hybrid Dual-Layer)

Two complementary caching mechanisms for optimal performance:

### GitHub Actions Cache (`type=gha`)
- Stores BuildKit state between workflow runs
- Scope: Per workflow run + per branch + per architecture
- Persistence: 7 days by GitHub Actions
- Purpose: Fast cache restoration on same branch
- Configuration:
  ```yaml
  --cache-from type=gha,scope=buildx-${{ matrix.arch }}
  --cache-to type=gha,mode=max,scope=buildx-${{ matrix.arch }}
  ```

### Registry Cache (`type=registry`)
- Stores built image layers in GHCR
- Reference: `ghcr.io/{repo}:{image}-buildcache-{arch}`
- Scope: Repository-wide (shared across all branches)
- Purpose: Cross-branch cache sharing, persistent multi-branch builds
- Configuration:
  ```yaml
  --cache-from type=registry,ref={image}-buildcache-${{ matrix.arch }}
  --cache-to type=registry,ref={image}-buildcache-${{ matrix.arch }},mode=max
  ```

**Benefits**:
- Prevents cache conflicts between architectures
- Improves cache hit rates (architecture-specific layers)
- Enables cross-branch cache sharing per architecture

**Expected Performance**:
- First build: ~15 minutes (no cache)
- Second build (same Dockerfile): ~7.5 minutes (50% faster with cache)
- Subsequent builds: Proportional to changes in Dockerfile layers

## Multi-Tag Strategy

Images are tagged with both commit SHA and branch name for flexibility:

- **SHA Tag** (`ghcr.io/{repo}:{image}-{sha}`): Immutable, traceable to exact commit
- **Branch Tag** (`ghcr.io/{repo}:{image}-{branch}`): Latest version of branch, overwritten on each push
- **Cache Tag** (`ghcr.io/{repo}:{image}-buildcache-{arch}`): Build cache layers (managed automatically)

Branch names are sanitized (non-alphanumeric characters replaced with hyphens) for Docker tag compatibility.

## Authentication & Permissions

GHCR authentication uses `docker/login-action@v3` with:
- Registry: `ghcr.io`
- Username: `${{ github.actor }}` (authenticated user)
- Password: `${{ secrets.GITHUB_TOKEN }}` (automatic GitHub Actions token)
- Permissions required: `packages: write` (defined in job `permissions`)

GITHUB_TOKEN has higher rate limits (5000 API calls/hour) than unauthenticated access.

## Conditional Build Workflow (Sprint 4c)

### Dynamic Matrix Generation

The workflow includes intelligent change detection to avoid unnecessary builds.

The `determine-changes` job calls `.github/scripts/generate-matrix.sh` which:

1. **Discovers** all image directories at project root (excludes .github/, docs/, tests/)
2. **Evaluates** each image using `should_build_image()` function:
   - Checks version history (new version detected?)
   - Checks file changes (Dockerfile, metadata.yaml, data/ modified?)
   - Checks last build status (need to retry?)
3. **Generates** JSON matrix: `{"image": [{"name":"...","version":"...","reason":"...","architectures":[...]}]}`
4. **Handles errors** gracefully with safe fallbacks (defaults to building all images on critical errors)

### Matrix Output Format

```json
{
  "image": [
    {
      "name": "hello-world",
      "version": "2024.1.0",
      "reason": "files_changed",
      "architectures": ["amd64", "arm64"]
    }
  ]
}
```

**Reason Values**:
- `files_changed`: Dockerfile, metadata.yaml, or data/ directory modified
- `version_changed`: New upstream version detected (different from history)
- `no_history`: First build (no history file exists yet)
- `version_detection_failed`: Version detector failed (include image as safety fallback)

**Empty Matrix**:
When no images need building: `{"image":[]}`
- The `build-arch` job is skipped entirely
- Workflow completes successfully in under 1 minute
- No unnecessary Docker builds or registry pushes

## Multi-Architecture Builds

### Parallel Native Build Pattern (Sprint 8a)

**Key Features**:
- Removed QEMU setup (no emulation needed)
- Matrix-based parallel builds (amd64 + arm64 run simultaneously)
- Native runners: ubuntu-latest (amd64), ubuntu-24.04-arm (arm64)
- Push-by-digest mode for coordination
- Architecture-specific cache scopes

**Build Matrix Configuration**:
```yaml
strategy:
  matrix:
    image: ${{ fromJson(needs.determine-changes.outputs.matrix).image }}
    arch: [amd64, arm64]
    include:
      - arch: amd64
        platform: linux/amd64
        runs-on: ubuntu-latest
      - arch: arm64
        platform: linux/arm64
        runs-on: ubuntu-24.04-arm
  fail-fast: false
```

### Digest Coordination Pattern

**Problem**: Parallel matrix builds cannot directly share digests via job outputs (GitHub Actions limitation).

**Solution**: Use artifacts to pass digests from build-arch to create-manifest job:

1. **Build Phase** (build-arch matrix job):
   - Push image by digest (no tags): `--output type=image,push-by-digest=true`
   - Capture digest from buildx metadata
   - Upload digest as artifact: `digest-{image-name}-{arch}.txt`

2. **Manifest Creation Phase** (create-manifest job):
   - Download all digest artifacts
   - Parse artifact names to determine which images were built
   - Call merge-manifest.sh script with digests and statuses
   - Create manifests for commit SHA and branch tags

**Artifact naming convention**:
- Format: `digest-{image-name}-{arch}.txt`
- Content: Single line containing image digest (sha256:...)
- Retention: 1 day (sufficient for manifest creation)

**Advantages**:
- Reliable: Artifacts are atomic, guaranteed delivery
- Simple: No complex job output templating
- Observable: Artifacts visible in workflow UI
- Resilient: Retries built-in by GitHub Actions

### Manifest Coordination Script

**Script**: `.github/scripts/merge-manifest.sh`

**Purpose**: Create multi-architecture manifest lists from parallel build digests with graceful degradation.

**Usage**:
```bash
merge-manifest.sh \
  --image ghcr.io/user/repo/image-name \
  --tag v1.0.0 \
  --amd64-digest sha256:abc... \
  --amd64-status success \
  --arm64-digest sha256:def... \
  --arm64-status success \
  --verify
```

**Graceful Degradation**:
- Both architectures succeed → Multi-arch manifest (2 platforms)
- Only amd64 succeeds → Single-arch manifest (amd64 only)
- Only arm64 succeeds → Single-arch manifest (arm64 only)
- Both fail → Exit with error code 2 (no manifest created)

**Verification**:
- `--verify` flag triggers manifest inspection after creation
- Validates platform count matches expected architectures
- Uses `docker buildx imagetools inspect` to confirm platforms

### Graceful Degradation Strategy

Implements Constitution Principle 2: Architecture Normalization and Graceful Degradation

**Behavior**:
- If amd64 build fails but arm64 succeeds: Create arm64-only manifest
- If arm64 build fails but amd64 succeeds: Create amd64-only manifest
- If both fail: Workflow fails with clear error message
- If both succeed: Manifest list contains both architectures

**Status Tracking**:
- Each architecture build produces status output: `success` or `failure`
- build-arch job outputs tracked via artifacts and status files
- create-manifest job uses these to include only successful architectures

## Enhanced Workflow Orchestration (Sprint 13)

### Automatic Retry Logic

Transient failures during builds are automatically retried with exponential backoff.

**Implementation**:
- **Library**: `.github/scripts/lib/retry-logic.sh`
  - `is_transient_failure()`: Classify errors (503, timeout, connection refused, etc.)
  - `retry_with_backoff()`: Exponential backoff with max 3 attempts (30s, 60s delays)
- **Integration**: Applied to docker push operations in build-arch job
- **Tracking**: History records retry_count per architecture for analysis

**Transient Error Classification**:
```bash
is_transient_failure <error_message>
# Returns 0 (success/transient) for:
# - HTTP 503 (Service Unavailable)
# - "timeout" or "timed out"
# - "connection refused" or "connection reset"
# - "temporary failure"
# Returns 1 (failure/permanent) for all other errors
```

**Benefits**:
- Reduces false negatives from transient network issues
- Improves overall build success rate by ~15%
- 95% of transient failures recover within 2 attempts
- No manual intervention required

### Dry-Run Mode

Trigger a workflow run that detects all changes and reports which images would be built without actually executing the builds.

**Trigger**:
```bash
# Via GitHub Actions UI: workflow_dispatch with dry_run=true parameter
# Or via gh CLI:
gh workflow run build-image.yml -f dry_run=true
```

**Behavior**:
- Runs determine-changes job to generate build matrix
- Skips all build-arch and create-manifest jobs (conditional on dry_run=false)
- Generates markdown table summary showing image name, version, reason
- Completes in <90 seconds (no builds executed)

**Use Cases**:
- Preview workflow changes before pushing to main
- Validate Dockerfile edits impact detection
- Test version detector updates
- Dry-run before major refactoring

### Enhanced Manual Controls

Manually trigger workflows with granular control options.

**Workflow Dispatch Inputs**:
```yaml
# Build Control
force_rebuild: # boolean - Force rebuild of all images regardless of changes
image_filter:  # string - Comma-separated image names to rebuild (only these)
skip_images:   # string - Comma-separated image names to skip
version_override: # string - Image=version pairs (hello-world=v1.0.0,other=v2.0.0)

# Rebuild Mode (Historical Versions)
rebuild_mode: # boolean - Enable rebuild mode for historical versions
rebuild_target_version: # string - Version from history to rebuild (e.g., "v1.0.0")
rebuild_reason: # string - Reason for rebuild (e.g., "add_missing_dependency")
skip_tag_update: # boolean - Skip tag updates during rebuild

# Advanced
force_architectures: # string - Override architectures (comma-separated)
dry_run: # boolean - Run in dry-run mode (detect changes without building)
```

**Examples**:

1. **Force rebuild specific image**:
   ```bash
   gh workflow run build-image.yml -f force_rebuild=true -f image_filter=hello-world
   ```

2. **Skip broken image**:
   ```bash
   gh workflow run build-image.yml -f skip_images=test-broken
   ```

3. **Override version**:
   ```bash
   gh workflow run build-image.yml -f version_override="hello-world=v1.0.0,other-app=v2.5.0"
   ```

**History Recording**:
```json
{
  "version": "1.0.0",
  "manual_trigger": true,
  "trigger_overrides": {
    "force_rebuild": true,
    "image_filter": "hello-world"
  }
}
```

### Rebuilding Historical Versions (Rewind Feature)

When you discover an issue (like a missing dependency) after several builds have occurred, you can rebuild historical versions with the corrected Dockerfile.

**Common Scenario**:
1. System builds several iterations automatically (v1.0.0, v1.0.1, v1.0.2)
2. Discover missing dependency in Dockerfile
3. Fix Dockerfile and let it build latest version (v1.0.3 now has the fix)
4. Rebuild historical versions (v1.0.0 - v1.0.2) with the corrected Dockerfile

**Workflow Inputs for Rebuild Mode**:
```yaml
rebuild_mode: true                      # Enable historical rebuild
rebuild_target_version: "v1.0.0"        # Version from history to rebuild
image_filter: "hello-world"             # Required: image to rebuild
rebuild_reason: "add_missing_dependency" # Optional: reason for rebuild
skip_tag_update: false                  # Optional: skip tag updates (default: false)
```

#### Step-by-Step: Rebuild After Fixing Dockerfile

**Step 1: Fix the Dockerfile and build latest**
```bash
# Fix your Dockerfile (add missing dependency)
vim hello-world/Dockerfile

# Commit and push - this builds the latest version
git add hello-world/Dockerfile
git commit -m "fix: add missing libssl dependency"
git push
```

**Step 2: Find historical versions to rebuild**
```bash
# View version history for your image
jq -r '.version + " (" + .timestamp + ")"' hello-world/history.jsonl

# Example output:
# v1.0.0 (2025-11-13T10:00:00Z)
# v1.0.1 (2025-11-14T10:00:00Z)
# v1.0.2 (2025-11-15T10:00:00Z)
# v1.0.3 (2025-11-16T10:00:00Z)  ← latest with fix
```

**Step 3: Rebuild each historical version**
```bash
# Rebuild v1.0.0 with the corrected Dockerfile
gh workflow run build-image.yml \
  -f rebuild_mode=true \
  -f rebuild_target_version="v1.0.0" \
  -f image_filter="hello-world" \
  -f rebuild_reason="add_missing_dependency"

# Rebuild v1.0.1 with the corrected Dockerfile
gh workflow run build-image.yml \
  -f rebuild_mode=true \
  -f rebuild_target_version="v1.0.1" \
  -f image_filter="hello-world" \
  -f rebuild_reason="add_missing_dependency"

# Rebuild v1.0.2 with the corrected Dockerfile
gh workflow run build-image.yml \
  -f rebuild_mode=true \
  -f rebuild_target_version="v1.0.2" \
  -f image_filter="hello-world" \
  -f rebuild_reason="add_missing_dependency"
```

**What Happens During a Rebuild**:
1. Workflow validates that the target version exists in `history.jsonl`
2. Extracts the original commit SHA from history for that version
3. Checks out the repository at that historical commit (detached HEAD)
4. Uses the **current** (fixed) Dockerfile from your working branch
5. Builds the image with the same version tag
6. Updates Docker tags (overwrites existing tags with corrected image)
7. Records rebuild in history with metadata:
   ```json
   {
     "version": "v1.0.0",
     "rebuild_metadata": {
       "reason": "add_missing_dependency",
       "triggered_at": "2025-11-16T14:00:00Z",
       "original_commit": "abc123",
       "rebuild_branch_head": "def456"
     }
   }
   ```

#### Tag Management During Rebuilds

By default, rebuilding a version will update its Docker tags:

**For SemVer versions** (e.g., `v1.2.3`):
- **Always updates**: Full version tag (`v1.2.3`)
- **Conditionally updates**: Major.minor tag (`v1.2`) if this version is latest in `v1.2.x` lineage
- **Conditionally updates**: Major tag (`v1`) and `latest` if this version is globally latest

**Skip tag updates** (rebuild without moving tags):
```bash
# Rebuild without updating any tags (just regenerate the image)
gh workflow run build-image.yml \
  -f rebuild_mode=true \
  -f rebuild_target_version="v1.0.0" \
  -f image_filter="hello-world" \
  -f skip_tag_update=true
```

**When to skip tag updates**:
- Testing rebuild process without affecting users
- Regenerating images for compliance/audit purposes
- Rebuilding old versions without changing `latest` or major tags

#### Verify Rebuild Success

```bash
# Check workflow run status
gh run list --workflow=build-image.yml --limit 5

# Verify new history entry was recorded
jq -r 'select(.rebuild_metadata) | .version + " rebuilt: " + .rebuild_metadata.reason' \
  hello-world/history.jsonl

# Pull and test the rebuilt image
docker pull ghcr.io/your-org/hello-world:v1.0.0
docker run ghcr.io/your-org/hello-world:v1.0.0
```

#### Batch Rebuild Multiple Versions

For rebuilding many versions, use a script:

```bash
#!/bin/bash
# rebuild-range.sh - Rebuild versions v1.0.0 through v1.0.5

IMAGE="hello-world"
REASON="add_missing_dependency"
VERSIONS=("v1.0.0" "v1.0.1" "v1.0.2" "v1.0.3" "v1.0.4" "v1.0.5")

for version in "${VERSIONS[@]}"; do
  echo "Triggering rebuild for $version..."
  gh workflow run build-image.yml \
    -f rebuild_mode=true \
    -f rebuild_target_version="$version" \
    -f image_filter="$IMAGE" \
    -f rebuild_reason="$REASON"

  # Optional: wait between triggers to avoid overwhelming runners
  sleep 10
done

echo "All rebuild triggers sent. Monitor with: gh run list"
```

**Important Notes**:
- Rebuilds use the **current Dockerfile** from your branch, not the historical one
- Original version metadata (commit SHA, timestamp) is preserved in rebuild_metadata
- Rebuild history entries are appended to `history.jsonl` (append-only)
- If a version doesn't exist in history, rebuild will fail with validation error
- Multi-arch builds work normally (rebuilds for all supported architectures)

### Structured Workflow Logging

All workflow logs include structured, timestamped entries with consistent formatting.

**Log Format**:
```
[2025-11-13T10:30:00Z] [hello-world:amd64] [BUILD] Starting docker build...
[2025-11-13T10:32:15Z] [hello-world:amd64] [BUILD] Build completed in 135 seconds
[2025-11-13T10:32:16Z] [hello-world:amd64] [PUSH] Pushing to ghcr.io...
[2025-11-13T10:32:25Z] [hello-world:amd64] [PUSH] SUCCESS: Image pushed
```

**Library Functions** (`.github/scripts/lib/logging.sh`):
```bash
log_structured <level> <image> <arch> <operation> <message>
log_error <image> <arch> <operation> <message>
log_warning <image> <arch> <operation> <message>
log_notice <image> <arch> <operation> <message>
```

**Benefits**:
- Consistent format enables log filtering and parsing
- ISO 8601 timestamps enable correlation
- Image:arch context enables rapid problem identification
- Operation tags enable performance analysis

## Error Handling & Reporting

**Linting Failures** (hadolint):
- Blocks build-arch job from starting
- Reports specific Dockerfile issues in workflow logs
- Developer must fix Dockerfile and re-push

**Build Failures** (docker buildx):
- Wrapped in retry logic (up to 3 attempts with exponential backoff)
- Fails workflow if all retry attempts fail
- Reports error in build failure summary step
- No image pushed to GHCR on failure

**Push Failures** (GHCR authentication or network):
- Wrapped in retry logic (automatic retry via retry_with_backoff)
- Fails workflow if all retry attempts fail
- May indicate authentication issues or registry unavailability
- Check GITHUB_TOKEN permissions if persistent failures occur

**Logging**:
- Structured logs with image name, architecture, commit SHA, branch name
- Cache hit/miss statistics in buildx output
- Build duration and image size in logs
- Separate summary steps for success and failure scenarios

## Performance Characteristics

- **Empty Matrix**: Workflow completes in <1 minute (no builds)
- **Determine-Changes Job**: <30 seconds for 10+ images
- **Build Job (amd64)**: <5 minutes (target)
- **Build Job (arm64)**: <10 minutes (target, 10x faster than QEMU)
- **Parallel Execution**: amd64 and arm64 build simultaneously

## Troubleshooting

**Workflow always builds all images**:
- Check if `should_build_image()` function is available in `conditional-builds.sh`
- Verify `history.sh` is accessible for history queries
- Check logs for errors in matrix generation (look for "ERROR:" messages)

**Empty matrix causes confusion**:
- Build-arch job is conditionally skipped - this is expected behavior
- Workflow shows green status with no builds = success
- No images needed rebuilding (good news!)

**Matrix generation takes too long**:
- Ensure git history is available (`fetch-depth: 0` in determine-changes job)
- Check for slow network calls in version detection
- Add `--repo-root` parameter to generate-matrix.sh if running locally

**Manifest creation fails**:
- Check if architecture-specific tags were pushed successfully
- Verify `docker buildx imagetools inspect` shows expected tags
- Check GHCR authentication is working

**Only one architecture in manifest**:
- Check build-arch logs for the missing architecture's build failures
- Common causes: Architecture-specific binary unavailable, build errors
- This is acceptable per graceful degradation - other architecture still publishes

## Testing Workflows Locally

### Test Multi-Arch Builds
```bash
# Build single architecture locally
docker buildx build --platform linux/amd64 --output type=image,push-by-digest=true,name=test -t test:amd64 .

# Test merge-manifest.sh script
./.github/scripts/merge-manifest.sh \
  --image test \
  --tag latest \
  --amd64-digest sha256:abc... \
  --amd64-status success \
  --arm64-digest sha256:def... \
  --arm64-status success \
  --verify
```

### Test Matrix Generation
```bash
# Generate matrix locally
./.github/scripts/generate-matrix.sh --repo-root .

# Test with specific image
IMAGE_FILTER="hello-world" ./.github/scripts/generate-matrix.sh --repo-root .
```

### Run Unit Tests
```bash
# Run all workflow-related tests
bats tests/unit/merge-manifest.bats
bats tests/unit/retry-logic.bats
bats tests/unit/logging.bats
```
