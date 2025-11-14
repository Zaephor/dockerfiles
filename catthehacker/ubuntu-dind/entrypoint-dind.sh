#!/bin/bash
set -e

# Use /tmp for logs (writable by non-root users)
DOCKER_LOG="/tmp/docker.log"

# Check if Docker daemon is already running
if ! pgrep -x dockerd > /dev/null; then
    # Check if running as root (required for Docker daemon)
    if [ "$(id -u)" -ne 0 ]; then
        echo "WARNING: Not running as root (current user: $(id -un), uid: $(id -u))"
        echo "WARNING: Docker daemon requires root privileges and --privileged mode"
        echo "WARNING: Skipping Docker daemon startup"
        echo ""
        echo "To use Docker-in-Docker, run with:"
        echo "  docker run --privileged --user root ..."
        echo "  OR"
        echo "  In GitHub Actions: options: --privileged"
        echo ""
        echo "Continuing without Docker daemon..."
    else
        echo "Starting Docker daemon..."

        # Start dockerd in the background
        # Storage driver and other options are configured in /etc/docker/daemon.json
        dockerd \
            --host=unix:///var/run/docker.sock \
            --host=tcp://0.0.0.0:2375 \
            > "$DOCKER_LOG" 2>&1 &

        # Wait for Docker to be ready
        echo "Waiting for Docker to be ready..."
        timeout=30
        while ! docker info >/dev/null 2>&1; do
            sleep 1
            timeout=$((timeout - 1))
            if [ $timeout -le 0 ]; then
                echo "ERROR: Docker daemon failed to start within 30 seconds"
                if [ -f "$DOCKER_LOG" ]; then
                    echo "--- Docker daemon logs ---"
                    cat "$DOCKER_LOG"
                fi
                exit 1
            fi
        done

        echo "Docker daemon is ready"
    fi
else
    echo "Docker daemon already running"
fi

# Execute the provided command
exec "$@"
