#!/bin/bash
# looperd entrypoint (daemon path): when a factory zone is configured
# (LLM_PROVIDERS_JSON set), render ~/.pi/agent/models.json first so the pi
# agents looperd spawns resolve their providers; prime the pinned harnesses
# (factory-prime: steady state asserts offline and prints ONLY export lines
# the entrypoint evals — a PATH prefix onto /data/harnesses/bin plus one
# config dir per vendor, e.g. CODEX_HOME — all diagnostics to stderr); render
# the harness config files (render-harness; no-op when its blob env is
# unset); ensure ~/.looper exists; then exec the daemon. exec keeps looperd
# as PID 1 so it receives container signals directly. Any prep step that
# FAILs (named, stderr) exits the container: the daemon never starts on
# half-state. pi zones: prime prints nothing and render-harness is a no-op —
# the daemon path is unchanged apart from the two no-op spawns.
#
# With an explicit command (`docker run image looperd --version`) the command
# is exec'd directly instead — NO daemon prep runs at all (no models render,
# no harness priming): smoke tests and debugging bypass the daemon entirely.
set -euo pipefail

if [ "$#" -gt 0 ]; then
    exec "$@"
fi

if [ -n "${LLM_PROVIDERS_JSON:-}" ]; then
    node /render-models.mjs
else
    echo "entrypoint: LLM_PROVIDERS_JSON not set — skipping models.json render (bare interactive use)" >&2
fi

# Prime the pinned harnesses (spec §5), capturing stdout BEFORE eval:
# `eval "$(node /factory-prime.mjs)"` alone would swallow a non-zero exit
# (evaluating an empty string succeeds), but the assignment propagates it
# through set -e — a missing pin or half-installed harness stops the start.
prime_exports="$(node /factory-prime.mjs)"
eval "$prime_exports"

# Harness config files (spec §4): silent skip when FACTORY_HARNESS_CFG_JSON
# is unset (pi zones / bare interactive use); FAIL + exit on error.
node /render-harness.mjs

mkdir -p "$HOME/.looper"
exec looperd --config "$LOOPER_CONFIG"
