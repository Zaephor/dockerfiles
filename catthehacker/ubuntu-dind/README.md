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

## License

MIT - Same as the underlying catthehacker/ubuntu images

## Links

- **Base Images**: [catthehacker/docker_images](https://github.com/catthehacker/docker_images)
- **Source**: [zaephor/dockerfiles](https://github.com/zaephor/dockerfiles)
- **Issues**: [Report Issues](https://github.com/zaephor/dockerfiles/issues)
