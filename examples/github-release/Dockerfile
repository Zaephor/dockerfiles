FROM alpine:3.18

ARG VERSION=latest

RUN apk add --no-cache \
    ca-certificates \
    curl \
    && \
    curl -fsSL "https://github.com/example/example/releases/download/v${VERSION}/example-linux-amd64.tar.gz" | \
    tar xzf - -C /usr/local/bin/ && \
    chmod +x /usr/local/bin/example && \
    apk del curl ca-certificates

LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.description="Example application from GitHub Releases"

ENTRYPOINT ["example"]
CMD ["--version"]
