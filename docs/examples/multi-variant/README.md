# Multi-Variant Pattern

This example demonstrates building multiple variants of the same image (e.g., Debian and Alpine).

## Pattern Description

**Use this pattern when**:
- You want to provide multiple base image options (full vs. minimal)
- Users can choose between smaller (Alpine) or standard (Debian/Ubuntu) images
- All variants share the same version and binary

## How It Works

1. **Multiple Dockerfiles**: `Dockerfile` (default) and `Dockerfile.alpine` (variants)
2. **Same Version**: All variants detected from single `version_source`
3. **Separate Builds**: Each variant builds independently for each architecture
4. **Separate Tags**: Images tagged with variant suffix: `app:1.2.3` (Debian), `app:1.2.3-alpine` (Alpine)

## Configuration

```yaml
name: multi-variant-example
variants: [alpine]           # Create alpine variant

# All variants share same version detection:
version_source:
  type: github_releases
  repo: example/app
```

## File Structure

```
multi-variant-example/
├── Dockerfile               # Main variant (Debian)
├── Dockerfile.alpine        # Alpine variant
├── metadata.yaml            # Shared version config
└── README.md                # This file
```

## Customization Steps

1. **Add variants in metadata.yaml**
   ```yaml
   variants: [alpine, slim, distroless]  # Add more variants
   ```

2. **Create Dockerfile.{variant} files**
   ```bash
   # For each variant listed:
   cp Dockerfile Dockerfile.alpine
   # Edit Dockerfile.alpine to use alpine base image
   ```

3. **Customize each variant**
   - `Dockerfile`: Default (Debian-based, full)
   - `Dockerfile.alpine`: Minimal (Alpine, ~5MB)
   - `Dockerfile.slim`: Slim (Debian slim, minimal deps)

## Building

Each variant builds independently:
- Debian variant: Builds with `Dockerfile`
- Alpine variant: Builds with `Dockerfile.alpine`
- All architectures: Both amd64 and arm64

Tags created:
- `app:1.2.3` (Debian main, amd64/arm64 manifest)
- `app:1.2.3-alpine` (Alpine, amd64/arm64 manifest)

## Size Comparison

Typical sizes for same application:

```
app:1.2.3           = 150 MB (Debian)
app:1.2.3-alpine    = 25 MB  (Alpine)
app:1.2.3-slim      = 75 MB  (Debian slim)
```

## Testing

```bash
# Validate metadata
.github/scripts/local-tools/validate-metadata.sh multi-variant-example

# Test version detection
.github/scripts/local-tools/test-version-detection.sh multi-variant-example

# Lint all Dockerfiles
.github/scripts/local-tools/lint-dockerfile.sh multi-variant-example
```

## Best Practices

1. **Keep Dockerfile and Dockerfile.{variant} in sync**
   - Same application version
   - Same binary/configuration
   - Only difference is base image and package manager

2. **Document differences in README**
   - Explain when to use each variant
   - List size/feature differences

3. **Test all variants**
   - Ensure each variant works independently
   - Smoke test each variant in CI

## Common Variants

### alpine
- **Base**: `alpine:latest`
- **Size**: ~5-30 MB
- **Use**: Minimal deployments, IoT, edge
- **Tradeoff**: Less tooling, some binaries may not support Alpine

### slim
- **Base**: `debian:X-slim` or `ubuntu:X`
- **Size**: ~50-100 MB
- **Use**: Balanced - smaller than full, more compatible than Alpine
- **Tradeoff**: Still substantial size

### distroless
- **Base**: `gcr.io/distroless/base`
- **Size**: ~2-10 MB
- **Use**: Security-focused, minimal attack surface
- **Tradeoff**: Very minimal, only what's needed to run

### full (default)
- **Base**: `debian:X` or `ubuntu:X`
- **Size**: ~100-300 MB+
- **Use**: Development, debugging, maximum compatibility
- **Tradeoff**: Larger images

## References

- [YAML Configuration Reference](../../docs/yaml-config-reference.md)
- [Dockerfile Best Practices](https://docs.docker.com/develop/dockerfile_best-practices/)
- [Alpine Linux](https://alpinelinux.org/)
