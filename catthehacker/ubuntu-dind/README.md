# catthehacker/ubuntu-dind

Docker-in-Docker (DinD) enabled versions of the popular [catthehacker/ubuntu](https://github.com/catthehacker/docker_images) images for GitHub Actions.

## What is This?

These images extend the `ghcr.io/catthehacker/ubuntu` base images by adding Docker Engine, allowing you to run Docker commands and build Docker images inside GitHub Actions workflows or other containerized environments.

## Variants

- **act-24.04**: Based on `ghcr.io/catthehacker/ubuntu:act-24.04` (Ubuntu 24.04 LTS)
- **act-22.04**: Based on `ghcr.io/catthehacker/ubuntu:act-22.04` (Ubuntu 22.04 LTS)

## Usage

### In GitHub Actions

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/zaephor/dockerfiles/catthehacker/ubuntu-dind:act-24.04
      options: --privileged
    steps:
      - uses: actions/checkout@v4

      - name: Build Docker image
        run: docker build -t myapp .

      - name: Run tests in Docker
        run: docker run myapp test
```

### Local Testing with act

```bash
# Use with nektos/act for local GitHub Actions testing
act -P ubuntu-latest=ghcr.io/zaephor/dockerfiles/catthehacker/ubuntu-dind:act-24.04
```

### Docker Run

```bash
# Run with privileged mode to allow Docker daemon to start
docker run --privileged -it ghcr.io/zaephor/dockerfiles/catthehacker/ubuntu-dind:act-24.04
```

## Features

- **Docker Engine**: Latest stable Docker CE
- **Docker Buildx**: Multi-platform build support
- **Docker Compose Plugin**: Compose V2 (docker compose)
- **Containerd**: Container runtime
- **Overlay2 Storage Driver**: Efficient layer management
- **BuildKit**: Modern build backend enabled by default
- **Health Check**: Automatic verification of Docker daemon readiness
- **Configurable Daemon**: Environment-based daemon.json configuration

## Verifying Installation

Once the container starts, you can verify the Docker installation:

```bash
# Check Docker version
docker --version

# Verify Docker daemon is running
docker info

# Check Buildx plugin
docker buildx version

# Check Compose plugin
docker compose version

# Verify multi-architecture support
docker buildx ls

# Inspect daemon configuration
cat /etc/docker/daemon.json
```

You can also inspect the image before running:

```bash
# View image metadata and labels
docker inspect ghcr.io/zaephor/dockerfiles/catthehacker/ubuntu-dind:act-24.04

# Check installed Docker version without running
docker run --rm ghcr.io/zaephor/dockerfiles/catthehacker/ubuntu-dind:act-24.04 docker --version
```

## Configuration

The DinD entrypoint supports several environment variables for customizing the Docker daemon:

### Registry Mirrors

Configure Docker registry mirrors to improve pull performance and reduce bandwidth:

```yaml
container:
  image: ghcr.io/zaephor/dockerfiles/catthehacker/ubuntu-dind:act-24.04
  options: --privileged
  env:
    DOCKER_REGISTRY_MIRRORS: "https://mirror.gcr.io,https://registry.internal.local"
```

### Insecure Registries

Allow connections to registries without valid TLS certificates:

```yaml
env:
  DOCKER_INSECURE_REGISTRIES: "registry.local:5000,10.0.0.5:5000"
```

### Storage Driver

Override the default overlay2 storage driver:

```yaml
env:
  DOCKER_STORAGE_DRIVER: "vfs"
```

### BuildKit

Disable BuildKit if needed (enabled by default):

```yaml
env:
  DOCKER_BUILDKIT_ENABLED: "false"
```

### Full Daemon Override

Provide a complete custom daemon.json:

```yaml
env:
  DOCKER_DAEMON_JSON: '{"storage-driver":"overlay2","log-driver":"json-file","log-opts":{"max-size":"10m"}}'
```

### User Mode

Run as a non-root user inside the container (useful for local development):

```bash
docker run --privileged -e HOST_UID=$(id -u) -e HOST_GID=$(id -g) \
  -it ghcr.io/zaephor/dockerfiles/catthehacker/ubuntu-dind:act-24.04
```

Without `HOST_UID`, the container runs in root mode (compatible with Gitea Runner and similar tools).

## Architecture Support

Both variants are built for:
- `linux/amd64`
- `linux/arm64`

## Tags

Each variant has the following tags:
- `act-24.04` - Always points to latest 24.04 build
- `act-22.04` - Always points to latest 22.04 build
- `latest` - Points to latest build (currently tracks act-24.04)

## Version Tracking

This image automatically rebuilds when the upstream `ghcr.io/catthehacker/ubuntu` images are updated, ensuring you always have the latest base image with Docker support.

## Requirements

**Important**: Docker-in-Docker requires `--privileged` mode to run the Docker daemon. This is required for:
- GitHub Actions: Set `options: --privileged` in container configuration
- Docker CLI: Use `docker run --privileged`
- act: Enabled by default when using `-P` flag

## Security Considerations

Running containers in privileged mode grants additional permissions. Only use these images in trusted environments like:
- CI/CD pipelines
- Local development
- Testing environments

## Troubleshooting

### Docker Daemon Not Starting

If the Docker daemon fails to start, check the startup logs:

```bash
# View daemon logs
cat /tmp/docker.log

# Check if dockerd is running
ps aux | grep dockerd

# Verify privileged mode is enabled
cat /proc/self/status | grep CapEff
```

**Common causes:**
- Container not running with `--privileged` flag
- Insufficient system resources (memory/disk)
- Conflicting daemon already running
- Storage driver incompatibility

### Permission Denied Errors

```
permission denied while trying to connect to the Docker daemon socket
```

**Solutions:**

```bash
# Verify docker.sock permissions
ls -la /var/run/docker.sock

# Ensure current user is in docker group (user mode only)
groups

# Check if daemon is actually running
docker info
```

If using user mode (`HOST_UID` set), ensure the user was added to the docker group:

```bash
# Inside container, verify group membership
id
```

### Storage Driver Issues

```
failed to start daemon: error initializing graphdriver: driver not supported
```

**Solution:** Override the storage driver:

```yaml
env:
  DOCKER_STORAGE_DRIVER: "vfs"  # Use vfs for maximum compatibility (slower)
```

Or check available drivers:

```bash
# List supported storage drivers
docker info | grep "Storage Driver"
```

### Health Check Failures

If the container reports unhealthy status:

```bash
# Manually run health check
docker info >/dev/null 2>&1 && echo "healthy" || echo "unhealthy"

# Check daemon status
systemctl status docker 2>/dev/null || echo "systemd not available (expected in container)"

# Review daemon logs for errors
cat /tmp/docker.log | tail -n 50
```

### Daemon Startup Timeout

```
ERROR: Docker daemon failed to start within 30 seconds
```

**Solutions:**

1. **Check system resources:**
   ```bash
   df -h  # Disk space
   free -h  # Memory
   ```

2. **Increase timeout:** The entrypoint script has a 30-second timeout. If your system is slow, you may need to modify the entrypoint.

3. **Inspect configuration:**
   ```bash
   cat /etc/docker/daemon.json
   jq . /etc/docker/daemon.json  # Verify valid JSON
   ```

### Registry Connection Issues

```
error pulling image: connection refused
```

**Solutions:**

1. **Check DNS resolution:**
   ```bash
   nslookup docker.io
   ping -c 3 registry-1.docker.io
   ```

2. **Test with insecure registry:**
   ```yaml
   env:
     DOCKER_INSECURE_REGISTRIES: "your-registry:5000"
   ```

3. **Verify registry mirrors:**
   ```bash
   cat /etc/docker/daemon.json | jq '.["registry-mirrors"]'
   docker info | grep "Registry Mirrors"
   ```

### User Mode Issues

When using `HOST_UID` and `HOST_GID`:

```bash
# Verify user was created correctly
id
getent passwd $(id -u)

# Check docker group membership
groups | grep docker

# Test docker access
docker ps

# If permission denied, check socket permissions
ls -la /var/run/docker.sock
```

### BuildKit Issues

```
failed to solve: failed to read dockerfile
```

**Solution:** Disable BuildKit if needed:

```yaml
env:
  DOCKER_BUILDKIT_ENABLED: "false"
```

Or check BuildKit status:

```bash
docker buildx ls
docker info | grep -i buildkit
```

### Container Exits Immediately

If the container starts and exits right away:

```bash
# Run with interactive mode to see errors
docker run --privileged -it ghcr.io/zaephor/dockerfiles/catthehacker/ubuntu-dind:act-24.04 /bin/bash

# Check entrypoint logs
docker logs <container-id>

# Verify the entrypoint script
cat /usr/local/bin/entrypoint-dind.sh
```

### Debug Mode

For detailed debugging, run commands manually:

```bash
# Start container with bash instead of entrypoint
docker run --privileged -it --entrypoint /bin/bash \
  ghcr.io/zaephor/dockerfiles/catthehacker/ubuntu-dind:act-24.04

# Inside container, manually start dockerd
dockerd --host=unix:///var/run/docker.sock --debug &

# Watch logs in real-time
tail -f /tmp/docker.log
```

## License

MIT - Same as the underlying catthehacker/ubuntu images

## Links

- **Base Images**: [catthehacker/docker_images](https://github.com/catthehacker/docker_images)
- **Source**: [zaephor/dockerfiles](https://github.com/zaephor/dockerfiles)
- **Issues**: [Report Issues](https://github.com/zaephor/dockerfiles/issues)
