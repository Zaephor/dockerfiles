#!/bin/bash
set -e

DOCKER_LOG="/tmp/docker.log"
DAEMON_JSON="/etc/docker/daemon.json"

# Generate Docker daemon configuration from environment variables
generate_daemon_json() {
    # Check if user provided full daemon.json override
    if [ -n "${DOCKER_DAEMON_JSON}" ]; then
        echo "Using custom daemon.json from DOCKER_DAEMON_JSON environment variable"
        echo "${DOCKER_DAEMON_JSON}" > "${DAEMON_JSON}"
        return
    fi

    # Start with base configuration
    local storage_driver="${DOCKER_STORAGE_DRIVER:-overlay2}"
    local buildkit_enabled="${DOCKER_BUILDKIT_ENABLED:-true}"

    # Build JSON using jq for proper formatting
    local config="{}"
    config=$(echo "$config" | jq --arg sd "$storage_driver" '. + {"storage-driver": $sd}')

    # Add BuildKit feature
    if [ "$buildkit_enabled" = "true" ]; then
        config=$(echo "$config" | jq '. + {"features": {"buildkit": true}}')
    fi

    # Add registry mirrors if specified
    if [ -n "${DOCKER_REGISTRY_MIRRORS}" ]; then
        echo "Configuring Docker registry mirrors: ${DOCKER_REGISTRY_MIRRORS}"
        # Convert comma-separated list to JSON array
        local mirrors_json
        mirrors_json=$(echo "${DOCKER_REGISTRY_MIRRORS}" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$";""))')
        config=$(echo "$config" | jq --argjson mirrors "$mirrors_json" '. + {"registry-mirrors": $mirrors}')
    fi

    # Add insecure registries if specified
    if [ -n "${DOCKER_INSECURE_REGISTRIES}" ]; then
        echo "Configuring insecure registries: ${DOCKER_INSECURE_REGISTRIES}"
        # Convert comma-separated list to JSON array
        local insecure_json
        insecure_json=$(echo "${DOCKER_INSECURE_REGISTRIES}" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$";""))')
        config=$(echo "$config" | jq --argjson insecure "$insecure_json" '. + {"insecure-registries": $insecure}')
    fi

    # Write generated configuration
    echo "$config" > "${DAEMON_JSON}"
    echo "Generated daemon.json:"
    cat "${DAEMON_JSON}"
}

# Configure Docker daemon before starting
generate_daemon_json

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

# Determine execution mode based on HOST_UID environment variable
if [ -n "${HOST_UID}" ]; then
    # User mode: Drop root privileges to match host user
    echo "User mode enabled: Dropping to UID=${HOST_UID}, GID=${HOST_GID:-$HOST_UID}"

    # Set default GID if not provided
    : "${HOST_GID:=$HOST_UID}"

    # Determine or create host-aligned user inside container

    # If UID exists, resolve its username
    if id -u "$HOST_UID" >/dev/null 2>&1; then
        EXISTING_USER=$(getent passwd "$HOST_UID" | cut -d: -f1)
        USERNAME="$EXISTING_USER"
    else
        # Create group if needed
        if ! getent group "$HOST_GID" >/dev/null; then
            groupadd -g "$HOST_GID" hostgroup
        fi

        # Create new user
        USERNAME="hostuser"
        useradd -m -u "$HOST_UID" -g "$HOST_GID" "$USERNAME"
    fi

    # Ensure user's primary GID matches host group
    USER_GID=$(id -g "$USERNAME")
    if [ "$USER_GID" -ne "$HOST_GID" ]; then
        # If HOST_GID does not exist, create it
        if ! getent group "$HOST_GID" >/dev/null; then
            groupadd -g "$HOST_GID" hostgroup
        fi
        usermod -g "$HOST_GID" "$USERNAME"
    fi

    # Add user to docker group if present
    if getent group docker >/dev/null; then
        usermod -aG docker "$USERNAME"
    fi

    # Drop to host user for the actual workload
    exec gosu "$USERNAME" "$@"
else
    # Root mode: Stay as root (Gitea Runner / upstream catthehacker/ubuntu compatibility)
    echo "Root mode: Running as root (compatible with Gitea Runner)"
    exec "$@"
fi
