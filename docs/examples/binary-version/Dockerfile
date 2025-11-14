FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    && \
    rm -rf /var/lib/apt/lists/*

ARG VERSION=latest

RUN curl -fsSL https://example.com/downloads/tool-${VERSION}-linux-amd64 -o /usr/local/bin/tool && \
    chmod +x /usr/local/bin/tool

LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.description="Example tool detected via binary --version"

ENTRYPOINT ["tool"]
CMD ["--version"]
