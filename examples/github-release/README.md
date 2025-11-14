# GitHub Releases Pattern

This example demonstrates building a Docker image from a project that publishes releases on GitHub.

## Pattern Description

**Use this pattern when**:
- Upstream project publishes official GitHub Releases
- Binaries are attached as release assets (e.g., `example-linux-amd64.tar.gz`)
- You want to track the latest stable release version

## How It Works

1. **Version Detection**: Queries GitHub API for latest release
2. **Tag Extraction**: Regex pattern extracts version from tag (e.g., `v1.2.3` → `1.2.3`)
3. **Binary Download**: Dockerfile downloads released binary during build
4. **Build**: Layers binary and dependencies into container

## Configuration Reference

See [docs/yaml-config-reference.md](../../docs/yaml-config-reference.md) for field details.

### Key Fields

```yaml
version_source: github_releases        # Use GitHub releases detection
source:
  github_repo: owner/repo              # GitHub repository
  version_regex: ^v(.+)$               # Extract version from tag
  prerelease_handling: stable           # Skip alpha/beta releases
```

## Customization Steps

1. **Update github_repo**: Point to your upstream project
   ```yaml
   github_repo: kubernetes/kubernetes
   ```

2. **Adjust version_regex**: Match your project's tag format
   ```yaml
   # For tags like: v1.2.3
   version_regex: ^v(.+)$

   # For tags like: release-1.2.3
   version_regex: ^release-(.+)$

   # For tags with suffixes: v1.2.3-extended
   version_regex: ^v(.+?)(?:-extended)?$
   ```

3. **Update download URL**: Point to correct release asset
   ```dockerfile
   curl -fsSL "https://github.com/owner/repo/releases/download/v${VERSION}/binary-linux-amd64.tar.gz"
   ```

4. **Adjust Dockerfile**: Add your application setup
   - Base image (alpine, debian, ubuntu, etc.)
   - Dependencies (apt-get, apk add)
   - Build steps
   - Entrypoint

## Testing

```bash
# Validate metadata
.github/scripts/local-tools/validate-metadata.sh github-release-example

# Test version detection
.github/scripts/local-tools/test-version-detection.sh github-release-example

# Lint Dockerfile
.github/scripts/local-tools/lint-dockerfile.sh github-release-example
```

## Real-World Examples

See repository for working example:
- `hello-world/` - Simple GitHub releases-based image

## References

- [GitHub Releases Documentation](https://docs.github.com/en/repositories/releasing-projects-on-github/)
- [GitHub API: Get latest release](https://docs.github.com/en/rest/releases/releases?apiVersion=2022-11-28#get-the-latest-release)
- [YAML Configuration Reference](../../docs/yaml-config-reference.md)
