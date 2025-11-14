# Hello World

A minimal multi-architecture container for testing and demonstration purposes.

## Variants

This image is available in multiple variants:

- **`default`** - Alpine-based (3.19)
- **`alpine`** - Alpine 3.18
- **`scratch`** - Minimal from-scratch build

## Architectures

- `linux/amd64`
- `linux/arm64`

## Usage

```bash
# Pull and run the default variant
docker run ghcr.io/zaephor/dockerfiles/hello-world:latest

# Run a specific variant
docker run ghcr.io/zaephor/dockerfiles/hello-world:alpine
docker run ghcr.io/zaephor/dockerfiles/hello-world:scratch
```

## Output

```
Hello from Alpine World - Version 1.0.0
Architecture: x86_64
```

## Source

Built from [zaephor/dockerfiles](https://github.com/zaephor/dockerfiles) repository.
