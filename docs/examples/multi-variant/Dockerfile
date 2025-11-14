FROM debian:12-slim

ARG VERSION=latest

RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    && \
    curl -fsSL "https://example.com/downloads/app-${VERSION}-linux-amd64.tar.gz" | \
    tar xzf - -C /usr/local/bin/ && \
    chmod +x /usr/local/bin/app && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.description="Example application - Debian variant"

ENTRYPOINT ["app"]
CMD ["--version"]
