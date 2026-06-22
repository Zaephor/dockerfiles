# Binary Version Detection Pattern

This example demonstrates detecting a tool's version by running the binary's `--version` command.

## Pattern Description

**Use this pattern when**:
- Tool prints its version when you run `tool --version`
- Version is embedded in the binary (not in a GitHub repo)
- You need to test if version detection works in the built image

## How It Works

1. **Build Image**: Dockerfile installs/downloads the tool
2. **Version Detection**: CI runs the installed binary with `--version` flag
3. **Regex Extraction**: Parses output to extract version number
4. **Build & Tag**: Creates image tagged with detected version

## Configuration Reference

```yaml
version_source:
  type: binary_version
  binary_path: /usr/local/bin/tool        # Path in image
  version_regex: 'version ([0-9.]+)'      # Regex to extract version
  # version_flags: --version              # optional flag to get version
```

### Key Fields

- **binary_path**: Absolute path inside the container
- **version_regex**: Regex with capture group `()` to extract version (bash ERE: use `[0-9]`, not `\d`)
  - Must have exactly one capture group that extracts the version number
  - Example: `'version ([0-9.]+)'` matches "version 1.2.3" and extracts "1.2.3"
- **version_flags**: Optional flag passed to binary (e.g., `--version`, `-v`, `version`)

## Customization Steps

1. **Set binary_path**: Point to where you install the tool in Dockerfile
   ```yaml
   binary_path: /usr/local/bin/myapp
   ```

2. **Adjust version_flags**: Match your tool's version flag
   ```yaml
   version_flags: --version            # Most common
   version_flags: -v                   # Some tools use short flag
   version_flags: version              # Some use subcommand
   ```

3. **Update version_regex**: Match your tool's version output format (bash ERE: use `[0-9]`, not `\d`)
   ```yaml
   # Output: "tool version 1.2.3" → Extract: "1.2.3"
   version_regex: 'tool version ([0-9.]+)'

   # Output: "v1.2.3" → Extract: "1.2.3"
   version_regex: 'v([0-9.]+)'

   # Output: "Version: 1.2.3 (build xyz)" → Extract: "1.2.3"
   version_regex: 'Version: ([0-9.]+)'
   ```

4. **Test locally before building**
   - Install tool in Docker: `docker run -it ubuntu bash`
   - Run: `/usr/local/bin/tool --version`
   - Check output format matches your regex

## Testing

```bash
# Validate metadata
.github/scripts/local-tools/validate-metadata.sh binary-version-example

# Test version detection
.github/scripts/local-tools/test-version-detection.sh binary-version-example

# Lint Dockerfile
.github/scripts/local-tools/lint-dockerfile.sh binary-version-example
```

## Debugging Version Regex

If version detection fails, test your regex pattern:

```bash
# Run in container to see actual output
docker run -it --rm myimage --version

# Match output against regex (in bash)
version_output="tool version 1.2.3"
if [[ $version_output =~ version\ (.+) ]]; then
    echo "Captured: ${BASH_REMATCH[1]}"
fi
```

## Examples From Community

- **kubectl**: Path `/usr/local/bin/kubectl`, version_flags `--client`, version_regex `Client Version: v([0-9.]+)`
- **helm**: Path `/usr/local/bin/helm`, version_flags `version --short`, version_regex `v([0-9.]+)`
- **docker**: Path `/usr/bin/docker`, version_flags `--version`, version_regex `Docker version ([0-9.]+),`

## References

- [YAML Configuration Reference](../../docs/yaml-config-reference.md)
- [Troubleshooting Guide](../../docs/troubleshooting.md)
