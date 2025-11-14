# Troubleshooting Guide: Docker Build System

This guide covers common issues encountered when building and managing Docker images in this repository, with focus on Sprint 8 native ARM64 builds.

---

## Build Failures

### Problem: Docker build command fails during build-arch job

**Symptoms**:
- Workflow logs show docker buildx command returning non-zero exit code
- Error messages in build output (compiler errors, missing dependencies, etc.)
- Build status: FAILURE

**Root Cause Categories**:
1. **Dockerfile errors**: Invalid syntax, missing base images, broken commands
2. **Architecture-specific issues**: Binary/library not available for target architecture
3. **Network issues**: Cannot download dependencies, registry timeout
4. **Resource constraints**: Out of disk space, memory limits
5. **Cache conflicts**: Stale cache causing build failures

**Diagnosis Steps**:

1. **Check workflow logs for specific error**:
   - Go to GitHub Actions workflow run
   - Click on "Build ${{ matrix.image.name }}" job
   - Look for error message in "Build and push image by digest" step
   - Search logs for "ERROR", "failed", "cannot"

2. **Verify Dockerfile syntax**:
   ```bash
   # Run hadolint locally
   docker run --rm -i hadolint/hadolint:latest-alpine < {image}/Dockerfile
   ```

3. **Check for architecture-specific issues**:
   - Verify base image supports target architecture:
     ```bash
     # Check image supports amd64
     docker run --platform linux/amd64 {base-image} uname -m
     # Check image supports arm64
     docker run --platform linux/arm64 {base-image} uname -m
     ```
   - Look for hardcoded architecture assumptions in RUN commands

4. **Test build locally**:
   ```bash
   # Test amd64 locally
   docker buildx build --platform linux/amd64 --file {image}/Dockerfile {image}

   # Test arm64 locally (if amd64 system, will use QEMU - slow)
   docker buildx build --platform linux/arm64 --file {image}/Dockerfile {image}
   ```

**Solution Steps**:

1. **Fix Dockerfile errors** (syntax, missing dependencies):
   ```bash
   # Edit Dockerfile
   vim {image}/Dockerfile

   # Test locally
   docker buildx build --platform linux/amd64 --file {image}/Dockerfile {image}

   # Commit and push
   git add {image}/Dockerfile
   git commit -m "fix: correct Dockerfile issues"
   git push
   ```

2. **Fix architecture-specific issues**:
   - Add multi-arch build instructions if needed:
     ```dockerfile
     # Example: Install architecture-specific binary
     RUN if [ "$(uname -m)" = "aarch64" ]; then \
       apt-get install -y binary-arm64; \
     else \
       apt-get install -y binary-amd64; \
     fi
     ```
   - OR use base images with better arch support

3. **Clear cache if stale**:
   - Go to GitHub Actions settings → Actions → General → "Cleanup policies"
   - OR push to trigger rebuild (new build, same commit won't use cache)

4. **Check resource limits**:
   - If disk full: Check previous artifacts in workflow
   - If memory error: Optimize Dockerfile layers or increase build machine capacity (out of scope)

---

## Digest Coordination Failures

### Problem: Digest file missing or invalid when creating manifest

**Symptoms**:
- Workflow logs show error in "Create manifests for all images" step
- Error: "No such file or directory" for digest-*.txt
- Or: "Invalid digest format" error
- Manifest creation skipped or fails

**Root Cause Categories**:
1. **Build failed silently**: Build artifact wasn't uploaded because build failed
2. **Artifact upload failed**: Network issue, GitHub Actions failure
3. **Artifact download failed**: Timeout, missing artifact, permission issue
4. **Digest format invalid**: Incorrect digest extraction from buildx metadata

**Diagnosis Steps**:

1. **Verify build artifacts uploaded**:
   - In workflow UI, click "Artifacts" in build summary
   - Look for `digest-{image-name}-{arch}` artifacts
   - If missing: Previous build step failed

2. **Check build-arch job status**:
   - Go to "Build {image-name} ({arch})" job
   - Look for "Build and push image by digest" step
   - Check if step completed successfully (green checkmark)
   - If red: See [Build Failures](#build-failures) section

3. **Verify digest file contents**:
   - In "Create manifests" job, check "Download digest artifacts" step
   - Look for output showing downloaded files
   - If empty: No artifacts downloaded (previous build failed)

4. **Check digest format in logs**:
   - Search logs for "Captured digest"
   - Should look like: `sha256:0123456789abcdef...` (64 hex characters)
   - If different format: Issue with buildx metadata extraction

**Solution Steps**:

1. **If build failed**: Fix build issue first (see [Build Failures](#build-failures))

2. **If artifact upload failed**:
   - Re-run workflow: GitHub Actions UI → Re-run failed jobs
   - This will rebuild with same commit SHA

3. **If digest extraction failed**:
   - Check buildx version in workflow:
     ```bash
     # In build-image.yml
     docker/setup-buildx-action@v3  # Latest recommended
     ```
   - Verify metadata-file path in build command matches extraction:
     ```bash
     # Build command creates: /tmp/build-metadata.json
     # Extract command reads from: /tmp/build-metadata.json
     ```

---

## Manifest Creation Failures

### Problem: Multi-architecture manifest fails to create

**Symptoms**:
- Workflow logs show error in "Create manifests for all images" step
- Error: "docker buildx imagetools create" fails
- Or: "Failed to create manifest"
- Images pushed but no manifest list created

**Root Cause Categories**:
1. **Both architectures failed**: No digests available to create manifest
2. **GHCR authentication failed**: Cannot access registry for manifest creation
3. **Invalid digest format**: Passed to imagetools with wrong format
4. **Manifest verification failed**: Created manifest doesn't match expected platforms
5. **Registry API error**: GHCR temporary unavailability

**Diagnosis Steps**:

1. **Check architecture-specific build status**:
   - Look at artifacts from build-arch job:
     - `status-{image-name}-amd64.txt` should contain "success" or "failure"
     - `status-{image-name}-arm64.txt` should contain "success" or "failure"
   - If both are "failure": Go to [Build Failures](#build-failures)

2. **Verify GHCR authentication**:
   - Check "Log in to GitHub Container Registry" step
   - Should complete successfully (green checkmark)
   - Verify token has correct permissions (`packages: write`)

3. **Check merge-manifest.sh execution**:
   - Look for "Creating manifest for ..." log lines
   - Check for error messages after each call
   - If error: Related to digest format or registry access

4. **Verify manifest with imagetools**:
   - Look for "docker buildx imagetools inspect" output
   - Should show platform entries (amd64, arm64, or single arch)
   - If missing: Manifest verification failed

**Solution Steps**:

1. **If both architectures failed**:
   - Fix underlying build issues first (see [Build Failures](#build-failures))

2. **If GHCR auth failed**:
   - Verify token has `packages:write` permission:
     ```bash
     # Check workflow job permissions
     # In .github/workflows/build-image.yml:
     # permissions:
     #   packages: write
     ```
   - Verify GITHUB_TOKEN is set (automatic in GitHub Actions)
   - If custom registry credentials: Check docs/security-best-practices.md

3. **If merge-manifest.sh fails**:
   - Run script locally with test digests:
     ```bash
     ./.github/scripts/merge-manifest.sh \
       --image ghcr.io/{repo}/test-image \
       --tag latest \
       --amd64-digest "sha256:0000000000000000000000000000000000000000000000000000000000000000" \
       --amd64-status success \
       --arm64-digest "" \
       --arm64-status failure \
       --verify
     ```
   - Check script output for specific error
   - See merge-manifest.sh for debugging options

4. **If registry API error**:
   - Workflow will retry automatically (built into merge-manifest.sh)
   - If persistent: GHCR may be experiencing issues
   - Wait and re-run workflow after registry recovers

---

## Performance Issues

### Problem: Build takes longer than expected (>600 seconds)

**Symptoms**:
- Workflow logs show build duration warning: "Build duration exceeded 10 minute target"
- Actual duration: 600+ seconds
- ARM64 builds consistently slow

**Root Cause Categories**:
1. **Large base image**: Base image has many layers/is large
2. **Many dependencies**: Dockerfile installs many packages
3. **Missing layer cache**: Cache not available, rebuilding all layers
4. **Network issues**: Slow package downloads
5. **Infrastructure issues**: Runner overloaded or slow disk

**Diagnosis Steps**:

1. **Check build log for layer timings**:
   - Look for "Step X/Y : RUN ..." lines with durations
   - Identify slowest layers
   - Example: "Step 5: Installing dependencies ... took 120s"

2. **Compare amd64 vs arm64 timing**:
   - Expected: arm64 slightly slower (native runner is similar speed)
   - If arm64 10x slower: May be QEMU (shouldn't happen with Sprint 8a native runners)
   - Query history:
     ```bash
     jq -r '[.version, (.architectures.amd64.duration_seconds // 0), (.architectures.arm64.duration_seconds // 0)]' image-name/history.jsonl | tail -5
     ```

3. **Check cache hit rate**:
   - Look for "Cache HIT" vs "Cache MISS" in build logs
   - If all misses: Cache not working
   - If hits but still slow: Cache isn't effective (layers are expensive)

4. **Monitor history trend**:
   ```bash
   # Get last 20 build durations
   jq -r '.version + ": " + (.architectures.amd64.duration_seconds | tostring) + "s"' image-name/history.jsonl | tail -20
   ```

**Solution Steps**:

1. **Optimize Dockerfile**:
   - Reorder commands: Most-changing commands last (maximize cache)
   - Combine RUN commands: Reduces layer count
   - Remove unnecessary dependencies
   - Example:
     ```dockerfile
     # Slow: Each RUN is separate layer
     RUN apt-get update
     RUN apt-get install -y package1
     RUN apt-get install -y package2

     # Fast: Single layer, better cache
     RUN apt-get update && apt-get install -y \
       package1 \
       package2
     ```

2. **Use more specific base images**:
   - Alpine: Smaller and faster (if compatible)
   - Slim variants: Fewer packages pre-installed
   - Example: `alpine:latest` (5MB) vs `ubuntu:latest` (70MB)

3. **Clear registry cache if needed**:
   - Registry cache can become stale/large
   - Manual solution: Nothing needed (automatic garbage collection)
   - Can push to force new build without cache

4. **Accept longer build times**:
   - If optimization isn't feasible, update documentation
   - 600+ seconds is still acceptable (10 minutes)
   - Warnings are informational, not failures

---

## History File Issues

### Problem: History file missing or corrupted

**Symptoms**:
- `{image-name}/history.jsonl` file doesn't exist
- File exists but contains invalid JSON
- jq queries fail with parse errors
- Build history not being recorded

**Root Cause Categories**:
1. **First build**: History file hasn't been created yet
2. **File corruption**: Build interrupted while writing
3. **Permission error**: Cannot write to image directory
4. **Git issue**: File not committed, missing from checkout

**Diagnosis Steps**:

1. **Check if file exists**:
   ```bash
   ls -la {image-name}/history.jsonl
   # Should exist after first successful build
   ```

2. **Validate JSON format**:
   ```bash
   jq -c '.' {image-name}/history.jsonl > /dev/null && echo "Valid" || echo "Invalid JSON"
   ```

3. **Check file permissions**:
   ```bash
   ls -la {image-name}/
   # Check if directory is writable
   ```

4. **Check git status**:
   ```bash
   git status {image-name}/history.jsonl
   # Should show committed or staged
   ```

**Solution Steps**:

1. **If file doesn't exist yet**:
   - This is expected after first build
   - File will be created by first successful build
   - No action needed

2. **If JSON is invalid**:
   - Restore from git if possible:
     ```bash
     git checkout {image-name}/history.jsonl
     ```
   - If not in git: May need to manually recreate valid JSONL

3. **If permission error**:
   - Check workflow has write permissions
   - Verify GitHub Actions token scope (packages:write)
   - See docs/security-best-practices.md

4. **If missing from checkout**:
   - Add to gitignore check (should be committed):
     ```bash
     cat .gitignore | grep history
     # Should NOT contain history.jsonl pattern
     ```
   - Commit first build history:
     ```bash
     git add {image-name}/history.jsonl
     git commit -m "init: add build history for {image}"
     git push
     ```

---

## General Troubleshooting Tips

### Get detailed logs

```bash
# View full workflow logs
# GitHub UI: Actions → Workflow run → Job → Steps

# Or check git log for build history
git log --oneline {image-name}/history.jsonl | head -10
```

### Test changes locally before pushing

```bash
# Lint Dockerfile
docker run --rm -i hadolint/hadolint:latest-alpine < {image}/Dockerfile

# Build locally
docker buildx build --platform linux/amd64 --file {image}/Dockerfile {image}

# Check metadata.yaml validity (if present)
jq '.' {image}/metadata.yaml > /dev/null
```

### Check for common issues

```bash
# Verify all Dockerfiles have correct syntax
for dockerfile in */Dockerfile; do
  echo "Checking $dockerfile..."
  docker run --rm -i hadolint/hadolint:latest-alpine < "$dockerfile" || echo "FAILED: $dockerfile"
done

# Verify all history files are valid JSON
for history in */history.jsonl; do
  jq -c '.' "$history" > /dev/null && echo "OK: $history" || echo "INVALID: $history"
done
```

### Monitor build performance

```bash
# Get average build time for image
for image in hello-world test-app; do
  echo "$image:"
  jq -r '.architectures.amd64.duration_seconds // null' "$image/history.jsonl" | \
    tail -10 | \
    awk '{sum+=$1; count++} END {if(count>0) printf "  Average: %.1f seconds\n", sum/count; else print "  No data"}'
done
```

---

## Local Testing Script Issues

### Problem: validate-metadata.sh fails

**Symptoms**:
- Exit code 1: Metadata validation failed
- Exit code 2: Missing dependencies (yq, jq)
- Exit code 3: Invalid arguments
- Exit code 4: metadata.yaml not found

**Diagnosis Steps**:

```bash
# Check if script exists and is executable
ls -la .github/scripts/local-tools/validate-metadata.sh

# Run with verbose output
.github/scripts/local-tools/validate-metadata.sh --verbose IMAGE_NAME

# Check for YAML syntax errors
yq eval '.' IMAGE_NAME/metadata.yaml

# Check required fields
yq eval '.name, .version_source, .source' IMAGE_NAME/metadata.yaml
```

**Solution Steps**:

1. **If YAML syntax error**: Fix YAML indentation (2 spaces)
2. **If required fields missing**: Add name, version_source, source
3. **If enum value invalid**: Check version_source is one of: github_releases, binary_version, docker_tag, http_json
4. **If dependencies missing**: Install yq and jq

### Problem: test-version-detection.sh fails

**Symptoms**:
- Exit code 1: Version detection failed
- Exit code 4: metadata.yaml or detector not found
- Error: "GitHub API rate limit exceeded"

**Diagnosis Steps**:

```bash
# Check if detector script exists
ls .github/scripts/detectors/github-releases.sh

# Test detector directly
.github/scripts/detectors/github-releases.sh IMAGE_NAME

# Check GitHub API rate limits
gh api rate_limit

# Check GitHub token is set
echo $GITHUB_TOKEN
```

**Solution Steps**:

1. **If detector not found**: Verify version_source value matches detector name (underscores → hyphens)
2. **If rate limit exceeded**: Set GITHUB_TOKEN environment variable
   ```bash
   export GITHUB_TOKEN=your_token_here
   .github/scripts/local-tools/test-version-detection.sh IMAGE_NAME
   ```
3. **If detection fails**: Check source configuration matches detector expectations
4. **If regex mismatch**: Verify version_regex pattern matches your tags
   ```bash
   # Test regex against real tags
   git tag | grep -E 'YOUR_REGEX_HERE'
   ```

### Problem: check-conditional-build.sh shows wrong result

**Symptoms**:
- Says "would skip" when it should build
- Says "would build" when nothing changed
- Incorrect version comparison

**Diagnosis Steps**:

```bash
# Check git changes
git diff --name-only HEAD~1 | grep IMAGE_NAME

# Check history file
cat IMAGE_NAME/history.jsonl

# Check detected version
.github/scripts/local-tools/test-version-detection.sh IMAGE_NAME

# Check latest version in history
tail -1 IMAGE_NAME/history.jsonl | jq '.version'
```

**Solution Steps**:

1. **If git changes not detected**: Commit changes first (script looks at HEAD~1)
2. **If history file invalid**: Restore from git: `git checkout IMAGE_NAME/history.jsonl`
3. **If version mismatch**: Verify version detection works: `test-version-detection.sh IMAGE_NAME`
4. **If first build**: No history file is normal (will build)

### Problem: lint-dockerfile.sh reports errors

**Symptoms**:
- hadolint linting errors
- File not found errors
- No Dockerfiles found

**Diagnosis Steps**:

```bash
# Check Dockerfile exists
ls IMAGE_NAME/Dockerfile*

# Run hadolint directly
hadolint IMAGE_NAME/Dockerfile

# Check for variant Dockerfiles
ls -la IMAGE_NAME/Dockerfile.*
```

**Solution Steps**:

1. **If hadolint not installed**: Install with `apt-get install hadolint`
2. **If linting errors**: Fix according to hadolint rules or add .hadolint.yaml exceptions
3. **If file not found**: Create Dockerfile in IMAGE_NAME directory
4. **If variant error**: Ensure Dockerfile.{variant} exists for declared variants

## Still Having Issues?

### Check these resources

1. **README.md**: Project overview and quick reference
2. **CONTRIBUTING.md**: How to add images and test locally
3. **docs/yaml-config-reference.md**: Complete metadata.yaml schema
4. **docs/** directory: Complete documentation of build system and workflows
7. **docs/adr/**: Architecture Decision Records explaining key decisions
8. **GitHub Issues**: Search for similar problems

### Escalation

For issues not covered here:
1. Check GitHub Actions logs for specific error messages
2. Review constitution principles for expected behavior
3. Open an issue with:
   - Workflow run URL
   - Error messages (full logs)
   - Steps to reproduce
   - Expected vs actual behavior
