# factory-agent-base — Node + the pi coding agent, driven headlessly by
# looperd. Upstream-tracking GHCR lane (zaephor/dockerfiles): version comes
# from metadata.yaml (http_json → npm latest) as the VERSION build-arg; no
# pins live here by design. entrypoint.sh + render-models.mjs are
# byte-locked to containers/agent-base by tests/test_dockerfiles.py —
# edit there, copy here.
FROM node:24-bookworm-slim

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ripgrep curl jq ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# --ignore-scripts is a factory supply-chain stance (pi ships no build
# scripts); never relax it on this lane either.
ARG VERSION
RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent@${VERSION}

COPY entrypoint.sh render-models.mjs /
RUN chmod 0755 /entrypoint.sh /render-models.mjs

ENTRYPOINT ["/entrypoint.sh"]
