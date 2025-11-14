# 0001. Native ARM64 Runners for Multi-Arch Builds

**Status**: Accepted
**Date**: 2025-11-13
**Decision Maker(s)**: Project Maintainer

## Context

### Background

The project needed to support multi-architecture Docker image builds (amd64 and arm64) to serve diverse deployment environments - from cloud servers (amd64) to Raspberry Pi and cloud ARM instances (arm64).

Initial approach used QEMU emulation on amd64 runners to build arm64 images. This worked but was slow:
- **QEMU build times**: 30-45 minutes for large images
- **Performance ratio**: 10-30x slower than native builds
- **Build queuing**: With 50+ images, total build time became prohibitive

### Problem Statement

Scaling to 50+ images with QEMU emulation would make CI builds take hours, making rapid iteration impractical. Development feedback loop would be unacceptably long:
- Developer pushes change
- Wait 2+ hours for multi-arch builds
- Iterate

Solution needed to accelerate arm64 builds without sacrificing multi-architecture support or image quality.

## Decision

We use native ARM64 runners (`ubuntu-24.04-arm`) for arm64 builds instead of QEMU emulation on amd64 runners.

### Implementation Details

**GitHub Actions Matrix**:
- amd64: Runs on `ubuntu-latest` (native amd64)
- arm64: Runs on `ubuntu-24.04-arm` (native ARM64)

**Architecture**:
1. Matrix job triggers both runners in parallel
2. Each runner builds only its native architecture
3. Push-by-digest pattern coordinates outputs
4. Manifest creation step merges digests into multi-arch image

**Build Performance**:
- Native arm64: ~4-5 minutes for large images
- Native amd64: ~2-3 minutes
- Total for both: ~5 minutes (parallel execution)
- Historical QEMU approach: ~45 minutes

### Key Principles Applied

- **Principle 4**: Performance Over Simplicity - Accepts workflow complexity (dual runners, digest coordination) for 10x speedup
- **Principle 2**: Graceful Degradation - If arm64 runner unavailable, amd64-only manifest still succeeds

## Consequences

### Positive

- **10x faster builds** (measured: 45min QEMU → 4-5min native for large images)
- **Enables scaling to 50+ images** without prohibitive build times
- **More accurate builds** - native CPU instructions, not emulated
- **Better developer experience** - rapid feedback on changes
- **Reduced CI resource usage** - native builds more efficient

### Negative

- **More complex workflow** - dual matrix dimensions instead of single emulation approach
- **Digest coordination complexity** - requires push-by-digest pattern and digest artifact handling
- **Dependency on GitHub** - relies on GitHub providing ARM64 runners (availability risk)
- **Job artifact management** - requires downloading and merging digests between jobs
- **Split logs** - build logs across multiple parallel jobs (harder to debug)

### Neutral

- **Higher GitHub Actions minute usage** - Two jobs instead of one (but still within public repo limits)
- **Longer initial setup** - Matrix generation and runner provisioning slightly longer

## Alternatives Considered

### Alternative 1: Continue with QEMU Emulation

**Description**: Keep using QEMU to emulate arm64 on amd64 runners. Simple workflow, no coordination needed between runners.

**Rejected Because**:
- Build times prohibitive for 50+ images (45+ minutes per cycle)
- Not acceptable for rapid iteration/development
- Scales poorly as image count grows
- Underutilizes unlimited GitHub Actions minutes available in public repos

### Alternative 2: Cross-Compilation

**Description**: Cross-compile arm64 binaries on amd64 host, then package in arm64 base image.

**Rejected Because**:
- Not all upstream projects support cross-compilation
- Adds complexity to Dockerfiles (need cross-compilation toolchains)
- Doesn't help with base image layers (still need native builds for those)
- Limited applicability (only works for compiled projects, not for packaging existing binaries)

### Alternative 3: ARM-Only (Skip amd64)

**Description**: Publish only arm64 images, dropping amd64 support.

**Rejected Because**:
- Many users still need amd64 (cloud servers, older hardware)
- Eliminates large use case
- Goes against goal of scaling to diverse deployments

## Implementation Timeline

- **Sprint 8a**: Native ARM64 runners implementation
- **Sprint 13**: Workflow optimization and retry logic
- **Ongoing**: Monitoring performance metrics, tuning cache strategies

## References

- GitHub Actions: [Native ARM64 runners](https://github.blog/changelog/2024-01-30-github-actions-macos-14-large-and-arm64-support-is-generally-available/)
- Push-by-digest pattern: [ADR-0002](0002-push-by-digest.md)
- Related documentation: [performance.md](../performance.md), [workflows.md](../workflows.md)
