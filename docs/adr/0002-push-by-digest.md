# 0002. Push-by-Digest Manifest Coordination

**Status**: Accepted
**Date**: 2025-11-13
**Decision Maker(s)**: Project Maintainer

## Context

### Background

Native ARM64 runners (ADR-0001) enabled 10x faster multi-arch builds. However, parallel builds on different runners create a coordination challenge: how do we combine amd64 and arm64 images into a single multi-architecture manifest list?

Standard approach would be to use `docker buildx build --push` with multi-platform flag, but this only works on a single runner.

### Problem Statement

When building multi-arch images on separate runners:
1. amd64 runner builds amd64 image
2. arm64 runner builds arm64 image
3. Need to combine into multi-arch manifest list

Options:
- Option A: Push separately, manually create manifest (coordination complexity)
- Option B: One runner waits for other to finish, then creates manifest (serializes builds)
- Option C: Push images, then extract digests, create manifest in separate step

## Decision

Use push-by-digest pattern (Option C):
1. Each runner pushes its architecture image, captures digest (SHA256)
2. Runners upload digest as GitHub Actions artifact
3. Final step downloads all digests, creates manifest list combining them

### Implementation Details

**Workflow Structure**:
```
build-amd64 (ubuntu-latest)
  ├─ docker buildx build --push
  ├─ Extract digest: sha256:abc123...
  └─ Upload artifact: amd64-digest.txt

build-arm64 (ubuntu-24.04-arm)
  ├─ docker buildx build --push
  ├─ Extract digest: sha256:xyz789...
  └─ Upload artifact: arm64-digest.txt

create-manifest (ubuntu-latest)
  ├─ Download amd64-digest.txt
  ├─ Download arm64-digest.txt
  ├─ Create manifest list combining both
  └─ Push manifest to registry
```

**Digest Format**:
```
Pushed: ghcr.io/owner/image@sha256:abc123...
Manifest: sha256:abc123...
Config: sha256:def456...
```

### Key Principles Applied

- **Principle 4**: Performance Over Simplicity - Accepts complex coordination for parallel builds
- **Principle 2**: Graceful Degradation - If one arch fails, can still push single-arch manifest

## Consequences

### Positive

- **Parallel builds** - amd64 and arm64 build simultaneously (not serially)
- **Enables native runners** - Necessary for architecture-specific builds on separate runners
- **Clear digest tracking** - SHA256 hashes ensure image integrity
- **Reproducible manifests** - Exact digest references ensure consistency

### Negative

- **Complex workflow logic** - Digest extraction and manifest creation add steps
- **Artifact management** - Need to upload/download digests between jobs
- **Debugging complexity** - Digest mismatches or manifest creation failures harder to diagnose
- **More moving parts** - More things that can go wrong

## Alternatives Considered

### Alternative 1: docker buildx with Multi-Platform

**Description**: Use `docker buildx` with `--platform amd64,arm64` flag to build both architectures on single runner.

**Rejected Because**:
- Still requires QEMU emulation (doesn't support native builds)
- Negates the 10x speedup advantage of native runners
- Defeats the purpose of ADR-0001

### Alternative 2: Serial Builds on Single Runner

**Description**: amd64 runner builds both, using QEMU for arm64.

**Rejected Because**:
- Slow (back to QEMU performance)
- Doesn't use GitHub's provided ARM64 runners

### Alternative 3: Manifest Tool in Separate Service

**Description**: Push digests to external service for manifest coordination.

**Rejected Because**:
- Adds external dependency
- Complexity without benefit over GitHub Actions artifacts
- Harder to debug (external service logs)

## Implementation Timeline

- **Sprint 8a**: Initial push-by-digest implementation
- **Sprint 8b**: Performance monitoring and digest validation
- **Sprint 13**: Enhanced error handling and retry logic

## Graceful Degradation

If one architecture fails:
- Push successful digest to registry
- Create single-arch manifest (not ideal but functional)
- Log as partial success in build history

Example:
- amd64 build succeeds, pushed
- arm64 build fails
- System creates amd64-only manifest instead of full multi-arch

## References

- Docker push-by-digest pattern: [Build and push](https://docs.docker.com/build/ci/github-actions/multi-platform/)
- Native ARM64 runners: [ADR-0001](0001-native-arm64-runners.md)
- Related documentation: [workflows.md](../workflows.md), [architecture-detection.md](../architecture-detection.md)
