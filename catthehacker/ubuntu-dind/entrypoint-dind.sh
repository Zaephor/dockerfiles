#!/bin/bash
set -e

DOCKER_LOG="/tmp/docker.log"

# Create host-matching group if needed
if ! getent group "$HOST_GID" >/dev/null; then
    groupadd -g "$HOST_GID" hostgroup
fi

# Create host-matching user if needed
if ! id -u "$HOST_UID" >/dev/null 2>&1; then
    useradd -m -u "$HOST_UID" -g "$HOST_GID" hostuser
fi

# Start dockerd only when running as root
if [ "$(id -u)" -eq 0 ]; then
    if ! pgrep -x dockerd >/dev/null; then
        echo "Starting Docker daemon..."

        dockerd \
            --host=unix:///var/run/docker.sock \
            --host=tcp://0.0.0.0:2375 \
            > "$DOCKER_LOG" 2>&1 &

        echo "Waiting for Docker to be ready..."
        timeout=30
        while ! docker info >/dev/null 2>&1; do
            sleep 1
            timeout=$((timeout - 1))
            if [ $timeout -le 0 ]; then
                echo "ERROR: Docker daemon failed to start within 30 seconds"
                cat "$DOCKER_LOG"
                exit 1
            fi
        done
        echo "Docker daemon is ready"
    fi
else
    echo "Not root; skipping dockerd startup"
fi

# Drop to host user for the actual workload
exec gosu "$HOST_UID:$HOST_GID" "$@"
