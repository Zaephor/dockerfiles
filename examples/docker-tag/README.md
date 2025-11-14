# Docker Tag Source Pattern

This example demonstrates tracking a version from another Docker image in a registry.

## Pattern Description

**Use this pattern when**:
- Your application depends on a specific Docker base image
- You want to automatically update when the base image updates
- Base image is maintained elsewhere (e.g., official Python, Node.js, Go)

## How It Works

1. **Monitor Registry**: Queries Docker registry for tags on specified image
2. **Filter Tags**: Regex pattern selects which tags to consider
3. **Extract Version**: Latest matching tag becomes the image version
4. **Rebuild**: When new tag appears, automatically rebuilds image

## Configuration Reference

```yaml
version_source: docker_tag
source:
  docker_image: library/python            # Image to monitor
  tag_pattern: "^3\\.(1[0-9]|[0-9])$"    # Only 3.10, 3.11, 3.12, etc.
```

### Key Fields

- **docker_image**: Image name (can include registry hostname)
- **tag_pattern**: Regex to filter which tags to consider
  - Match only stable versions
  - Exclude pre-releases, distroless variants, etc.

## Customization Steps

1. **Set docker_image**: Image you depend on
   ```yaml
   docker_image: library/python           # Official Python
   docker_image: library/node              # Official Node.js
   docker_image: golang:latest             # Or any other image
   ```

2. **Adjust tag_pattern**: Filter to versions you want
   ```yaml
   # Python: Match 3.10, 3.11, 3.12 (not 3.9, not distroless, not slim)
   tag_pattern: "^3\\.(1[0-9]|[0-9])$"

   # Node.js: Match 18.x and 20.x LTS
   tag_pattern: "^(18|20)\\."

   # Go: Match stable releases (1.21.0, not 1.21.0-rc1)
   tag_pattern: "^1\\.[0-9]+\\.[0-9]+$"

   # Match everything
   tag_pattern: ".*"
   ```

3. **Update Dockerfile**: Use detected version as needed
   ```dockerfile
   FROM python:3.11-slim
   # CI will rebuild when new 3.11.x tag appears
   ```

## Testing

```bash
# Validate metadata
.github/scripts/local-tools/validate-metadata.sh docker-tag-example

# Test version detection
.github/scripts/local-tools/test-version-detection.sh docker-tag-example

# Lint Dockerfile
.github/scripts/local-tools/lint-dockerfile.sh docker-tag-example
```

## Common Examples

### Official Images (No Registry Prefix)

```yaml
docker_image: library/python
docker_image: library/node
docker_image: library/golang
docker_image: library/ubuntu
```

### Third-Party Registries (Full Path)

```yaml
docker_image: ghcr.io/example/image
docker_image: quay.io/example/image
docker_image: mcr.microsoft.com/windows/servercore
```

## References

- [Docker Hub Official Images](https://hub.docker.com/search?q=&type=image&image_filter=official)
- [YAML Configuration Reference](../../docs/yaml-config-reference.md)
- [Troubleshooting Guide](../../docs/troubleshooting.md)
