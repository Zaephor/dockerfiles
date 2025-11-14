# Performance Monitoring and Metrics

Comprehensive guide to build performance tracking, metrics capture, querying, and optimization.

## Overview

The system tracks build performance metrics including duration, cache hit rates, and image sizes. Performance warnings are surfaced as workflow annotations when builds exceed targets.

**Key Performance Targets**:
- **AMD64 builds**: Target <5 minutes, warning threshold 600 seconds (10 minutes)
- **ARM64 builds**: Target <10 minutes, warning threshold 600 seconds
- **Cache hit rate**: Target >85% (indicates good layer reuse)
- **Image size change**: Warning if >20% increase (indicates Dockerfile bloat)

## Performance Metrics Capture

### What is Captured

Per architecture (amd64, arm64):
1. **Build Duration**: Start timestamp, end timestamp, duration in seconds
2. **Cache Hit Rate**: Percentage of Docker layers served from cache
3. **Image Size**: Total image size in bytes (and human-readable format)
4. **Image Size Change**: Percentage change from previous build
5. **Retry Count**: Number of retries needed (for transient failures)

### Capture Mechanism

**Timestamps**:
1. Start timestamp: Captured at beginning of build-arch job
2. End timestamp: Captured after build completes (even on failure)
3. Duration: Calculated as difference (end - start)

**Cache Hit Rate**:
- Parsed from buildx output during build
- Calculated as: (cache hit layers / total layers) × 100

**Image Size**:
- Queried from Docker manifest after successful push
- Stored as both bytes (precise) and human-readable format (MB/GB)

**Location in Workflow**:
- Timestamps captured in build-arch job steps
- Metrics appended to `{image-name}/history.jsonl` in "Update build history" step

## History File Format

### Complete Build Record with Performance Data

```json
{
  "version": "1.2.3",
  "timestamp": "2025-11-13T10:30:00Z",
  "commit": "abc123def456",
  "branch": "main",
  "manual_trigger": false,
  "architectures": {
    "amd64": {
      "status": "success",
      "digest": "sha256:deadbeef...",
      "duration_seconds": 245,
      "start_timestamp": 1699790400,
      "end_timestamp": 1699790645,
      "cache_hit_rate": 88,
      "image_size_bytes": 149221376,
      "image_size_change_percent": 12,
      "retry_count": 0
    },
    "arm64": {
      "status": "success",
      "digest": "sha256:cafebabe...",
      "duration_seconds": 580,
      "start_timestamp": 1699790400,
      "end_timestamp": 1699790980,
      "cache_hit_rate": 91,
      "image_size_bytes": 158916608,
      "image_size_change_percent": 8,
      "retry_count": 1,
      "retry_reasons": ["timeout"]
    }
  }
}
```

**Backwards Compatibility**: Records from before Sprint 8b may lack duration/metrics fields. All queries use null-safe access (`// null` or `// 0`) to handle missing fields gracefully.

## Performance Warning System

Build duration warnings are automatically logged when builds exceed the 10-minute threshold.

### Warning Triggers

**Build Duration Warning**:
```bash
if [ ${duration} -gt 600 ]; then
  echo "::warning::Build duration exceeded 10 minute target for {image} ({arch}): {duration}s"
fi
```

**Cache Hit Rate Warning**:
```bash
if [ ${cache_hit_rate} -lt 50 ]; then
  echo "::warning::Cache hit rate low for {image}:{arch}: ${cache_hit_rate}% ({hits}/{total} layers)"
fi
```

**Image Size Increase Warning**:
```bash
if [ ${size_change_percent} -gt 20 ]; then
  echo "::warning::Image size increased ${size_change_percent}% for {image}:{arch}: ${prev_size} → ${curr_size}"
fi
```

### Warning Output Format

GitHub Actions warning annotations appear in workflow logs and PR checks:
```
::warning::Build duration exceeded 10 minute target for hello-world (arm64): 650s
::warning::Cache hit rate low for hello-world:amd64: 35% (12/35 layers)
::warning::Image size increased 22% for test-app:amd64: 150 MB → 183 MB
```

**Expected Frequency**:
- Zero warnings for well-optimized builds
- Warnings indicate optimization opportunities (Dockerfile changes, cache effectiveness, infrastructure)

## Querying Build Performance History

### Using jq to Analyze history.jsonl Files

All examples use null-safe access (`// null` or `// 0`) for backwards compatibility.

### Duration Queries

**Get average duration over last 10 builds (amd64)**:
```bash
jq -r '.architectures.amd64.duration_seconds // null' image-name/history.jsonl | \
  tail -10 | \
  awk '{sum+=$1; count++} END {if(count>0) printf "Average: %.1f seconds\n", sum/count; else print "No data"}'
```

**Find slowest build (amd64)**:
```bash
jq -r '[.version, .architectures.amd64.duration_seconds // 0] | @csv' image-name/history.jsonl | \
  sort -t, -k2 -rn | \
  head -5 | \
  awk -F, '{printf "Version %s: %s seconds\n", $1, $2}'
```

**Find fastest build (amd64)**:
```bash
jq -r '[.version, .architectures.amd64.duration_seconds // 0] | @csv' image-name/history.jsonl | \
  sort -t, -k2 -n | \
  head -5 | \
  awk -F, '{printf "Version %s: %s seconds\n", $1, $2}'
```

**Count builds exceeding threshold (amd64)**:
```bash
jq -r 'select(.architectures.amd64.duration_seconds > 600) | .version' image-name/history.jsonl | wc -l
```

**Get duration trend (last 20 builds)**:
```bash
jq -r '.version + ": " + (.architectures.amd64.duration_seconds | tostring) + "s"' image-name/history.jsonl | tail -20
```

### Architecture Comparison Queries

**Compare amd64 vs arm64 performance**:
```bash
jq -r '[.version, (.architectures.amd64.duration_seconds // 0), (.architectures.arm64.duration_seconds // 0)] | @csv' image-name/history.jsonl | \
  tail -5 | \
  awk -F, '{printf "Version %s: amd64=%s, arm64=%s (diff=%.1f%%)\n", $1, $2, $3, ($3/$2-1)*100}'
```

**Compare cache hit rates (amd64 vs arm64)**:
```bash
jq -r '[.version, (.architectures.amd64.cache_hit_rate // 0), (.architectures.arm64.cache_hit_rate // 0)] | @csv' image-name/history.jsonl | \
  tail -10 | \
  awk -F, '{printf "Version %s: amd64=%s%%, arm64=%s%%\n", $1, $2, $3}'
```

### Cache Hit Rate Queries

**Get average cache hit rate over last 10 builds (amd64)**:
```bash
jq -r '.architectures.amd64.cache_hit_rate // null' image-name/history.jsonl | \
  tail -10 | \
  awk '{sum+=$1; count++} END {if(count>0) printf "Average: %.1f%%\n", sum/count; else print "No data"}'
```

**Find builds with low cache hit rates (<50%)**:
```bash
jq -r 'select(.architectures.amd64.cache_hit_rate < 50) | [.version, .architectures.amd64.cache_hit_rate] | @csv' image-name/history.jsonl | \
  awk -F, '{printf "Version %s: %s%% cache hit rate\n", $1, $2}'
```

### Image Size Queries

**Track image size over time (last 10 builds)**:
```bash
jq -r '[.version, .architectures.amd64.image_size_bytes] | @csv' image-name/history.jsonl | \
  tail -10 | \
  awk -F, '{printf "Version %s: %.1f MB\n", $1, $2/1024/1024}'
```

**Find largest image size**:
```bash
jq -r '[.version, .architectures.amd64.image_size_bytes // 0] | @csv' image-name/history.jsonl | \
  sort -t, -k2 -rn | \
  head -5 | \
  awk -F, '{printf "Version %s: %.1f MB\n", $1, $2/1024/1024}'
```

**Find builds with large size increases (>20%)**:
```bash
jq -r 'select(.architectures.amd64.image_size_change_percent > 20) | [.version, .architectures.amd64.image_size_change_percent] | @csv' image-name/history.jsonl | \
  awk -F, '{printf "Version %s: +%s%% size increase\n", $1, $2}'
```

### Retry Analysis Queries

**Count total retries across all builds**:
```bash
jq -r '[.architectures.amd64.retry_count // 0, .architectures.arm64.retry_count // 0] | add' image-name/history.jsonl | \
  awk '{sum+=$1} END {print "Total retries: " sum}'
```

**Find builds that required retries**:
```bash
jq -r 'select(.architectures.amd64.retry_count > 0 or .architectures.arm64.retry_count > 0) | [.version, (.architectures.amd64.retry_count // 0), (.architectures.arm64.retry_count // 0)] | @csv' image-name/history.jsonl | \
  awk -F, '{printf "Version %s: amd64=%s retries, arm64=%s retries\n", $1, $2, $3}'
```

**Analyze retry reasons**:
```bash
jq -r 'select(.architectures.amd64.retry_reasons) | [.version, (.architectures.amd64.retry_reasons | join(", "))] | @csv' image-name/history.jsonl | \
  awk -F, '{printf "Version %s: %s\n", $1, $2}'
```

## Performance Benchmarks

### Target Performance (Native ARM64 Runners)

**AMD64 Builds**:
- Target: <5 minutes
- Warning threshold: 600 seconds (10 minutes)
- Typical: 2-4 minutes for hello-world test image

**ARM64 Builds**:
- Target: <10 minutes (5-10x faster than QEMU)
- Warning threshold: 600 seconds (10 minutes)
- Typical: 4-8 minutes for hello-world test image

**Total Workflow End-to-End**:
- Parallel execution: 8-15 minutes (amd64 + arm64 simultaneously)
- Sequential overhead: lint + determine-changes + create-manifest (<2 minutes)

### Historical Context

**Sprint 6 (QEMU Emulation)**:
- ARM64 builds: 30-120 minutes
- Significant slowdown due to emulation overhead

**Sprint 8a (Native ARM64 Runners)**:
- ARM64 builds: 5-10 minutes
- **10x performance improvement** achieved
- Used ubuntu-24.04-arm runners for native execution

### Cache Performance

**Target Cache Hit Rate**: >85%

**Expected Cache Behavior**:
- First build (no cache): 0% cache hit rate, full build time
- Second build (same Dockerfile): 90-100% cache hit rate, <1 minute
- Changed Dockerfile layer: 50-70% cache hit rate (layers after change rebuilt)
- Changed base image: 0% cache hit rate (all layers invalidated)

**Cache Miss Scenarios**:
- Dependency updates (package version changes)
- Base image updates (FROM ubuntu:22.04 → ubuntu:24.04)
- Dockerfile refactoring (layer order changes)
- File COPY operations with changed content

## Performance Metrics Library

Library: `.github/scripts/lib/performance-metrics.sh`

### Available Functions

**calculate_cache_hit_rate**:
```bash
calculate_cache_hit_rate <buildx_output>
# Parses buildx output for cache statistics
# Returns: "88" (percentage only, no % symbol)
```

**get_image_size**:
```bash
get_image_size <image_digest>
# Queries Docker manifest for image size
# Returns: "142 MB" (human-readable format)
```

**calculate_size_change**:
```bash
calculate_size_change <current_size> <previous_size>
# Calculates percentage change between builds
# Returns: "+15" (percentage, positive/negative)
```

**format_size_human**:
```bash
format_size_human <bytes>
# Converts bytes to human-readable format
# Returns: "142 MB" (auto-scales to KB/MB/GB)
```

### Example Usage

```bash
#!/bin/bash
source .github/scripts/lib/performance-metrics.sh

# Capture build output
buildx_output=$(docker buildx build ... 2>&1)

# Calculate cache hit rate
cache_hit_rate=$(calculate_cache_hit_rate "$buildx_output")
echo "Cache hit rate: ${cache_hit_rate}%"

# Get image size
image_digest="sha256:abc123..."
image_size=$(get_image_size "$image_digest")
echo "Image size: $image_size"

# Compare with previous build
prev_size_bytes=142000000
curr_size_bytes=163300000
size_change=$(calculate_size_change "$curr_size_bytes" "$prev_size_bytes")
echo "Size change: ${size_change}%"
```

## Graceful Degradation

### Missing Timestamps

If timestamp capture fails, duration is recorded as null:
- Build continues successfully
- No impact on manifest creation
- Logged as warning: "Timestamps missing or invalid (graceful degradation)"
- Queries skip null values using `// null` or `// 0` patterns

### Missing Metrics

**Philosophy**: Performance data is nice-to-have, not critical. Missing metrics should never block builds.

**Behavior**:
- Cache hit rate calculation failure → record as null, continue build
- Image size query failure → record as null, continue build
- Retry count missing → treated as 0
- History record still created with available data

**Query Handling**:
All jq queries use null-safe access:
```bash
# Good: Handles missing fields gracefully
jq -r '.architectures.amd64.duration_seconds // 0'

# Bad: Will error if field missing
jq -r '.architectures.amd64.duration_seconds'
```

## Performance Optimization Tips

### Improving Build Duration

1. **Optimize Dockerfile layer order**:
   - Place frequently changing layers (COPY code) last
   - Place rarely changing layers (apt install) first
   - Use multi-stage builds to reduce final image size

2. **Use .dockerignore**:
   - Exclude unnecessary files from build context
   - Speeds up context transfer to Docker daemon

3. **Leverage BuildKit features**:
   - Use `RUN --mount=type=cache` for package managers
   - Use `COPY --link` to improve layer caching

4. **Minimize layer count**:
   - Combine related RUN commands with `&&`
   - Clean up temporary files in the same RUN layer

### Improving Cache Hit Rate

1. **Pin dependency versions**:
   - Use exact versions in package.json, requirements.txt, etc.
   - Prevents cache invalidation from upstream version changes

2. **Order operations correctly**:
   - Install dependencies before copying application code
   - Copy only dependency files first, install, then copy code

3. **Use architecture-specific caches**:
   - Already implemented in Sprint 8a
   - Separate cache for amd64 and arm64 prevents conflicts

4. **Avoid timestamps in Dockerfiles**:
   - Don't use `$(date)` or similar dynamic values
   - Use build args for version/timestamp if needed

### Reducing Image Size

1. **Use minimal base images**:
   - alpine, distroless, or scratch where possible
   - ubuntu:22.04 → alpine:3.18 can reduce size by 50-70%

2. **Multi-stage builds**:
   - Build in one stage, copy only runtime artifacts to final stage
   - Excludes build tools, compilers, dev dependencies

3. **Clean up in same layer**:
   ```dockerfile
   RUN apt-get update && apt-get install -y pkg \
       && rm -rf /var/lib/apt/lists/*
   ```

4. **Use .dockerignore**:
   - Exclude test files, docs, .git from final image

## Testing Performance Metrics

### Unit Tests

Test performance-metrics.sh library functions:

```bash
# Run performance metrics tests
bats tests/unit/performance-metrics.bats

# Expected: All calculations correct, format conversions valid
```

**Test Coverage**:
- Cache hit rate parsing from buildx output
- Image size format conversions (bytes → MB/GB)
- Size change percentage calculations
- Null-safe handling of missing data

### Integration Tests

Test full workflow with performance tracking:

```bash
# Trigger build with performance tracking
gh workflow run build-image.yml -f image_filter=hello-world

# Expected:
# - Build completes successfully
# - history.jsonl contains duration_seconds, cache_hit_rate, image_size_bytes
# - No warnings if build meets performance targets
# - Warning annotations if build exceeds thresholds
```

### Manual Performance Validation

```bash
# Check recent build has performance data
jq -r '.architectures.amd64 | keys' hello-world/history.jsonl | tail -1
# Expected output includes: duration_seconds, cache_hit_rate, image_size_bytes

# Verify all fields populated
jq -r 'select(.architectures.amd64.duration_seconds != null) | .version' hello-world/history.jsonl | wc -l
# Expected: Count matches total number of builds since Sprint 8b
```

## Summary

The performance monitoring system provides:
- **Automated Tracking**: Duration, cache hit rates, image sizes captured automatically
- **Proactive Warnings**: Alerts when builds exceed performance targets
- **Rich Query Interface**: jq-based queries for historical analysis
- **Graceful Degradation**: Missing metrics don't block builds
- **Optimization Insights**: Data-driven guidance for improving build performance

**Key Metrics to Monitor**:
1. Build duration trends (are builds getting slower?)
2. Cache hit rate patterns (cache effectiveness)
3. Image size changes (Dockerfile bloat detection)
4. Retry frequency (transient failure rate)
