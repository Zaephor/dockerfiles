#!/bin/bash
# looperd entrypoint: when a factory zone is configured (LLM_PROVIDERS_JSON
# set), render ~/.pi/agent/models.json first so the pi agents looperd spawns
# resolve their providers; ensure ~/.looper exists; then exec the daemon.
# exec keeps looperd as PID 1 so it receives container signals directly.
#
# With an explicit command (`docker run image looperd --version`) the command
# is exec'd directly instead — smoke tests and debugging bypass the daemon.
set -euo pipefail

if [ "$#" -gt 0 ]; then
    exec "$@"
fi

if [ -n "${LLM_PROVIDERS_JSON:-}" ]; then
    node /render-models.mjs
else
    echo "entrypoint: LLM_PROVIDERS_JSON not set — skipping models.json render (bare interactive use)" >&2
fi

mkdir -p "$HOME/.looper"
exec looperd --config "$LOOPER_CONFIG"
