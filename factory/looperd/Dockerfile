# factory-looperd — delivery-loop daemon for the software factory,
# SELF-CONTAINED: node + pi baked in, re-creating the factory-agent-base
# layers instead of FROMing the published image — their CI builds all
# images as a parallel matrix (no ordering), so a cross-image FROM would
# resolve to a stale or not-yet-published tag and break the build.
# Upstream-tracking GHCR lane (D10): looper version arrives as the VERSION
# build-arg (github_releases detection); pi floats on npm @latest because
# their CI injects exactly one build-arg — a pi-only upstream bump still
# needs a forced rebuild (workflow_dispatch force_rebuild=true
# image_filter=factory/looperd). No sha256 gates on this lane (they cannot
# be pre-written for future releases) — TLS-only downloads. The factory
# lane keeps checksum gates in containers/looperd, and `make audit-ghcr`
# pins the deployed versions to versions.env. entrypoint.sh,
# factory-prime.mjs and render-harness.mjs are byte-locked to
# containers/looperd/ (tests/test_dockerfiles.py); render-models.mjs is
# byte-locked to containers/agent-base/.
FROM node:24-bookworm-slim

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ripgrep curl jq ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# pi rides npm latest at build time (their CI injects only the looper
# VERSION arg — see header). --ignore-scripts is a factory supply-chain
# stance (pi ships no build scripts); never relax it on this lane either.
# hadolint ignore=DL3016
RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent@latest

ARG VERSION
RUN set -eux; \
    curl -fsSLO "https://github.com/nexu-io/looper/releases/download/v${VERSION}/looper-linux-amd64.tar.gz"; \
    curl -fsSLO "https://github.com/nexu-io/looper/releases/download/v${VERSION}/looperd-linux-amd64.tar.gz"; \
    curl -fsSL -o /tmp/gh-release.json https://api.github.com/repos/cli/cli/releases/latest; \
    gh_version="$(jq -r '.tag_name | ltrimstr("v")' /tmp/gh-release.json)"; \
    [ -n "$gh_version" ]; \
    curl -fsSLO "https://github.com/cli/cli/releases/download/v${gh_version}/gh_${gh_version}_linux_amd64.tar.gz"; \
    tar -xzf looper-linux-amd64.tar.gz; \
    tar -xzf looperd-linux-amd64.tar.gz; \
    tar -xzf "gh_${gh_version}_linux_amd64.tar.gz"; \
    install -m 0755 looper-linux-amd64 /usr/local/bin/looper; \
    install -m 0755 looperd-linux-amd64 /usr/local/bin/looperd; \
    install -m 0755 "gh_${gh_version}_linux_amd64/bin/gh" /usr/local/bin/gh; \
    rm -rf /tmp/gh-release.json looper-*.tar.gz looperd-*.tar.gz "gh_${gh_version}_linux_amd64.tar.gz" \
        looper-linux-amd64 looperd-linux-amd64 "gh_${gh_version}_linux_amd64"

# Replace the base entrypoint: render models.json for the pi agents looperd
# spawns, prime the pinned harnesses, render their config files, then exec
# the daemon (exec keeps looperd as PID 1 for signals). The priming scripts
# sit at / like render-models.mjs (the agent-base precedent — now COPY'd
# in, no longer inherited from the published base image).
COPY entrypoint.sh render-models.mjs factory-prime.mjs render-harness.mjs /

RUN chmod 0755 /entrypoint.sh /render-models.mjs /usr/local/bin/looper /usr/local/bin/looperd /usr/local/bin/gh \
    && chown root:root /usr/local/bin/looper /usr/local/bin/looperd /usr/local/bin/gh \
    && { userdel -r node 2>/dev/null || true; } \
    && useradd --uid 1000 --create-home --shell /usr/sbin/nologin looper

# Volume-init: bootstrap mounts FRESH NAMED volumes at /config and /data
# (factory-<zone>-config/-data). A named volume whose mountpoint is missing
# from the image mounts root:root 0755 — and this daemon path runs as
# looper (uid 1000), so every zone's FIRST start would EACCES at
# factory-prime's /data mkdirs and render-harness's /config writes.
# Pre-creating the dirs looper-owned makes docker copy that ownership into
# the fresh volume on first mount.
RUN mkdir -p /config /data \
    && chown 1000:1000 /config /data

ENV HOME=/home/looper \
    LOOPER_CONFIG=/home/looper/.looper/config.toml

USER 1000
WORKDIR /home/looper

ENTRYPOINT ["/entrypoint.sh"]
