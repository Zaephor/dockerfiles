# factory-looperd — delivery-loop daemon for the software factory, on the
# published factory-agent-base. Upstream-tracking GHCR lane (D10): looper
# version arrives as the VERSION build-arg (github_releases detection); no
# sha256 gates on this lane (they cannot be pre-written for future
# releases) — TLS-only downloads. The factory lane keeps checksum gates in
# containers/looperd, and `make audit-ghcr` pins the deployed digest to
# versions.env. entrypoint.sh is byte-locked to
# containers/looperd/entrypoint.sh (tests/test_dockerfiles.py).
# NOTE (spec §4): agent-base must publish first; a pi-only upstream bump
# does NOT retrigger this image — force a rebuild when adopting one.
# hadolint ignore=DL3007
FROM ghcr.io/zaephor/dockerfiles/factory-agent-base:latest

ARG VERSION
RUN set -eux; \
    curl -fsSLO "https://github.com/nexu-io/looper/releases/download/v${VERSION}/looper-linux-amd64.tar.gz"; \
    curl -fsSLO "https://github.com/nexu-io/looper/releases/download/v${VERSION}/looperd-linux-amd64.tar.gz"; \
    curl -fsSLO "https://github.com/cli/cli/releases/latest/download/gh_linux_amd64.tar.gz"; \
    tar -xzf looper-linux-amd64.tar.gz; \
    tar -xzf looperd-linux-amd64.tar.gz; \
    tar -xzf gh_linux_amd64.tar.gz; \
    install -m 0755 looper-linux-amd64 /usr/local/bin/looper; \
    install -m 0755 looperd-linux-amd64 /usr/local/bin/looperd; \
    install -m 0755 gh_*_linux_amd64/bin/gh /usr/local/bin/gh; \
    rm -rf looper-*.tar.gz looperd-*.tar.gz gh_linux_amd64.tar.gz \
        looper-linux-amd64 looperd-linux-amd64 gh_*_linux_amd64

# Replace the base entrypoint (render models.json for spawned pi agents,
# then exec the daemon — exec keeps looperd PID 1 for signals).
COPY entrypoint.sh /entrypoint.sh

RUN chmod 0755 /entrypoint.sh /usr/local/bin/looper /usr/local/bin/looperd /usr/local/bin/gh \
    && chown root:root /usr/local/bin/looper /usr/local/bin/looperd /usr/local/bin/gh \
    && { userdel -r node 2>/dev/null || true; } \
    && useradd --uid 1000 --create-home --shell /usr/sbin/nologin looper

ENV HOME=/home/looper \
    LOOPER_CONFIG=/home/looper/.looper/config.toml

USER looper
WORKDIR /home/looper

ENTRYPOINT ["/entrypoint.sh"]
