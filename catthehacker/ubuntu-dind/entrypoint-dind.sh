#!/bin/bash
set -e

# Ensure Docker daemon is running using shared init script
# This handles daemon.json generation and dockerd startup
# shellcheck source=init-docker.sh
source /usr/local/bin/init-docker.sh

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
