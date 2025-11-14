# 0005. Graceful Degradation Philosophy

**Status**: Accepted
**Date**: 2025-11-13
**Decision Maker(s)**: Project Maintainer

## Context

### Background

Multi-architecture Docker builds introduce failure scenarios:
- amd64 build succeeds, arm64 fails (or vice versa)
- Registry push succeeds for GHCR, fails for Docker Hub
- Smoke tests fail for one architecture
- Upstream binary unavailable for one architecture

Early design assumed all-or-nothing: if any step fails, entire build fails. This limits reliability and penalizes partial failures.

### Problem Statement

All-or-nothing approach has downsides:
1. One architecture failure blocks both architectures
2. One registry failure blocks all registries
3. Users unable to get any image if one piece fails
4. Not resilient to upstream issues (temporarily unavailable binaries, API outages)

Example failure scenario:
- amd64 build: success, 10 minutes
- arm64 build: fails due to binary not available
- Result: No image published (both architectures unavailable)
- Better: Publish amd64 image (50% availability > 0%)

## Decision

Implement graceful degradation: partial success is better than total failure.

### Implementation Details

**Single Architecture Failure**:
- If amd64 succeeds and arm64 fails: Publish amd64-only image
- If arm64 succeeds and amd64 fails: Publish arm64-only image
- Log as "partial success" in build history

**Registry Failure**:
- If GHCR push succeeds but Docker Hub fails: Published to GHCR, log Docker Hub failure
- Continue to next registry (don't stop at first failure)

**Smoke Test Failure**:
- If smoke test fails for one architecture: Mark build as failed for that architecture
- Other architectures continue building

**Build History Entry**:
```json
{
  "version": "1.2.3",
  "timestamp": "2025-11-13T10:30:00Z",
  "architectures": {
    "amd64": {"status": "success", "digest": "sha256:abc123..."},
    "arm64": {"status": "failed", "error": "binary not available"}
  },
  "registries": {
    "ghcr": {"status": "success"},
    "docker-hub": {"status": "failed", "error": "rate limit exceeded"}
  },
  "overall_status": "partial"
}
```

### Workflow Implementation

**Build Job**:
```yaml
build:
  strategy:
    matrix:
      arch: [amd64, arm64]
    fail-fast: false  # Don't stop if one arch fails
```

**Registry Push Job**:
```yaml
push:
  steps:
    - name: Push to GHCR
      continue-on-error: true  # Continue to Docker Hub if fails
    - name: Push to Docker Hub
      continue-on-error: true  # Continue to others if fails
```

**Manifest Creation**:
- If only one architecture available: Create single-arch manifest
- If both available: Create multi-arch manifest
- If neither: Fail entirely (error case)

### Key Principles Applied

- **Principle 2**: Graceful Degradation - Explicit implementation of this principle
- **Principle 6**: Multi-Registry Redundancy - Partial registry success acceptable

## Consequences

### Positive

- **Higher availability** - Users always get something (amd64 OR arm64 OR both)
- **Resilient to upstream issues** - Temporary binary unavailability doesn't block everything
- **Better user experience** - Can deploy even if one architecture fails
- **Reduced toil** - Fewer "fix the CI" emergency situations
- **Business continuity** - Services can run on available architectures

### Negative

- **Complexity** - Need to handle partial success in multiple places
- **User confusion** - May not realize missing architecture (amd64-only on arm64 machine pulls wrong image)
- **Silent failures** - Easy to miss that one architecture failed if not monitoring logs
- **Testing complexity** - Need tests for all partial failure modes

### Neutral

- **Increased logging** - More status messages needed to explain partial results
- **Different behavior** - Not typical for CI systems (used to all-or-nothing)

## Alternatives Considered

### Alternative 1: All-or-Nothing (Original Approach)

**Description**: Fail entire build if any component fails.

**Rejected Because**:
- Too strict for multi-component system
- One architecture unavailability blocks both
- Penalizes partial success
- Reduces resilience

### Alternative 2: Automatic Fallback to Single-Arch

**Description**: If multi-arch fails, automatically publish amd64-only without notification.

**Rejected Because**:
- Silent failures are dangerous
- Users unaware of missing architecture
- Need explicit notification of degradation

### Alternative 3: Manual Recovery Steps

**Description**: When partial failure occurs, operator manually reruns failed components.

**Rejected Because**:
- Requires manual intervention
- Slow recovery
- Not suitable for automated systems
- Doesn't scale with 50+ images

## Monitoring Partial Degradation

**Build history tracking**:
```bash
# Find partial success builds
jq 'select(.overall_status == "partial")' image/history.jsonl

# Find common failure modes
jq '.architectures[] | select(.status == "failed") | .error' image/history.jsonl | sort | uniq -c
```

**CI notifications**:
- Green for full success (both architectures)
- Yellow for partial success (one architecture)
- Red for complete failure (neither architecture)

**Documentation**:
- Log which architecture/registry failed
- Include error message and solution suggestions
- Make clear that partial success occurred

## User Expectations

**For Images with Multi-Arch Support**:
- amd64 AND arm64 both available (expected)
- If one missing: Clearly documented, not silent

**For Single-Arch Images**:
- Only one architecture available (by design)
- Clearly indicated in image metadata/documentation

## Testing Graceful Degradation

Must test all failure modes:
- ✓ Both architectures succeed
- ✓ amd64 succeeds, arm64 fails
- ✓ arm64 succeeds, amd64 fails
- ✓ Both fail (complete failure)
- ✓ One registry succeeds, other fails

## References

- Graceful degradation in UX: [Wikipedia](https://en.wikipedia.org/wiki/Fault_tolerance#Graceful_degradation)
- Related documentation: [architecture-detection.md](../architecture-detection.md), [workflows.md](../workflows.md)
