FROM ghcr.io/catthehacker/ubuntu:act-24.04

# Install Docker Engine for Docker-in-Docker
RUN apt-get update && \
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release && \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Configure Docker daemon for rootless/privileged operation
RUN mkdir -p /etc/docker && \
    echo '{"storage-driver": "overlay2", "features": {"buildkit": true}}' > /etc/docker/daemon.json

# Docker-in-Docker entrypoint wrapper
COPY entrypoint-dind.sh /usr/local/bin/entrypoint-dind.sh
RUN chmod +x /usr/local/bin/entrypoint-dind.sh

VOLUME /var/lib/docker

ENTRYPOINT ["/usr/local/bin/entrypoint-dind.sh"]
CMD ["/bin/bash"]
