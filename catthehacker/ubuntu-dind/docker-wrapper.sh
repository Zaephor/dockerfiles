#!/bin/bash
# docker-wrapper.sh - Wrapper for docker CLI that ensures dockerd is running
# This allows docker commands to work even when entrypoint is overridden

# Auto-start dockerd if needed (idempotent)
source /usr/local/bin/init-docker.sh 2>/dev/null || true

# Execute the real docker binary with all arguments
exec /usr/bin/docker.real "$@"
