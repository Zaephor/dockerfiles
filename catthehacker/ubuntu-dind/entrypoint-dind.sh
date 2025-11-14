#!/bin/bash
set -e

# Start Docker daemon if not already running
if ! pgrep -x dockerd > /dev/null; then
    echo "Starting Docker daemon..."

    # Start dockerd in the background
    # Storage driver and other options are configured in /etc/docker/daemon.json
    dockerd \
        --host=unix:///var/run/docker.sock \
        --host=tcp://0.0.0.0:2375 \
        > /var/log/docker.log 2>&1 &

    # Wait for Docker to be ready
    echo "Waiting for Docker to be ready..."
    timeout=30
    while ! docker info >/dev/null 2>&1; do
        sleep 1
        timeout=$((timeout - 1))
        if [ $timeout -le 0 ]; then
            echo "ERROR: Docker daemon failed to start within 30 seconds"
            cat /var/log/docker.log
            exit 1
        fi
    done

    echo "Docker daemon is ready"
fi

# Execute the provided command
exec "$@"
