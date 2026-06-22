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
version_source:
  type: github_releases                 # Use GitHub releases detection
  repo: owner/repo                      # GitHub repository
  # prerelease_filter: false            # optional: skip alpha/beta releases
  # auth_token_secret: GITHUB_TOKEN     # optional
```

## Customization Steps

1. **Update repo**: Point to your upstream project
   ```yaml
   repo: kubernetes/kubernetes
   ```

2. **Filter prereleases (optional)**: Skip alpha/beta releases
   ```yaml
   prerelease_filter: false   # set true to include prereleases
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
