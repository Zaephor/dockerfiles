# Cache Hit Rate Estimation

## Overview

The build system estimates Docker buildx cache hit rates by comparing current build duration against historical averages. This provides insights into cache effectiveness without requiring buildx metadata file parsing.

## How It Works

### Algorithm

```
Cache Hit Rate = 50% + ((avg_duration - current_duration) / avg_duration) * 50%
```

- **Baseline (50%)**: When current build time equals average
- **Good cache (>50%)**: When current build is faster than average
- **Poor cache (<50%)**: When current build is slower than average
- **Excellent cache (~100%)**: When current build is 2x faster than average
- **No cache (~0%)**: When current build is 2x slower than average

### Examples

| Average | Current | Improvement | Cache Rate | Interpretation |
|---------|---------|-------------|------------|----------------|
| 300s | 150s | 50% faster | 75% | Good cache hits |
| 300s | 75s | 75% faster | 87.5% | Excellent cache |
| 300s | 300s | Same speed | 50% | Baseline |
| 300s | 450s | 50% slower | 25% | Poor cache |
| 300s | 600s | 2x slower | 0% | No cache benefit |

## Implementation

### Script

`estimate-cache-hit-rate.sh IMAGE_DIR ARCH CURRENT_DURATION`

### Workflow Integration

```yaml
- name: Calculate cache hit rate
  run: |
    CURRENT_DURATION="${{ steps.end-time.outputs.duration }}"
    CACHE_HIT_RATE=$(.github/scripts/estimate-cache-hit-rate.sh \
      "${{ matrix.config.image.name }}" \
      "${{ matrix.config.arch }}" \
      "$CURRENT_DURATION")
```

### Data Storage

Cache hit rates are stored in `history.jsonl`:

```json
{
  "version": "sha256:...",
  "architectures": {
    "amd64": {
      "duration_seconds": 180,
      "cache_hit_rate": 70.0
    }
  }
}
```

## Baseline Calculation

- Uses **last 5 successful builds** for each architecture
- Excludes failed builds
- Returns `null` if insufficient history (< 1 build)
- Automatically adapts as codebase changes

## Limitations

1. **Estimation, not measurement**: Actual cache statistics from buildx would be more accurate
2. **Correlation, not causation**: Build time affected by many factors (CPU load, network, etc.)
3. **Linear mapping**: Real cache relationship may be non-linear
4. **Cold cache assumption**: Baseline assumes ~50% cache hit rate

## Benefits

1. **No buildx changes required**: Works with existing build infrastructure
2. **Historical tracking**: Shows cache performance trends over time
3. **Per-architecture**: Separate baselines for amd64 vs arm64
4. **Automatic adaptation**: Baseline updates as code evolves
5. **Simple interpretation**: 0-100% scale is intuitive

## Future Improvements

- Parse buildx `--metadata-file` for actual cache statistics
- Use exponential moving average for smoother baselines
- Detect and handle outliers (very slow builds)
- Add cache effectiveness warnings in PR comments
