#!/bin/bash
# agent-base entrypoint: render ~/.pi/agent/models.json from
# LLM_PROVIDERS_JSON, then exec the container command (looper, or a shell
# for interactive use).
#
# When LLM_PROVIDERS_JSON is unset (bare interactive use — no factory zone
# configured) we skip the render and note it on stderr, so `pi` can still run
# against whatever ~/.pi/agent/models.json the user mounted themselves.
# Set-but-EMPTY is NOT bare interactive use: it means a broken render
# upstream, so we fail fast exactly like the renderer CLI would (BL-9).
set -euo pipefail

if [ -n "${LLM_PROVIDERS_JSON:-}" ]; then
    node /render-models.mjs
elif [ -n "${LLM_PROVIDERS_JSON+x}" ]; then
    echo "entrypoint: LLM_PROVIDERS_JSON is set but empty — refusing to start (unset it for bare interactive use)" >&2
    exit 1
else
    echo "entrypoint: LLM_PROVIDERS_JSON not set — skipping models.json render (bare interactive use)" >&2
fi

exec "$@"
