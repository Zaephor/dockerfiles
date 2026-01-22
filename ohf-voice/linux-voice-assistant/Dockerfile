# Linux Voice Assistant - Voice satellite using ESPHome protocol
# Rebuild trigger: PulseAudio module-detect for USB audio input detection
# https://github.com/OHF-Voice/linux-voice-assistant
#
# Uses ESPHome voice assistant protocol for Home Assistant integration.

FROM python:3.11-slim-bookworm

ARG VERSION=main

ENV LANG=C.UTF-8
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
# - build-essential: Required for compiling some Python packages
# - portaudio19-dev: Audio I/O library (for soundcard package)
# - libmpv-dev/mpv: Media player for audio output
# - alsa-utils: ALSA tools for audio device discovery
# - pulseaudio: Required by soundcard library (interfaces with ALSA)
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    libportaudio2 \
    portaudio19-dev \
    libmpv-dev \
    mpv \
    alsa-utils \
    libasound2-plugins \
    pulseaudio \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Configure PulseAudio to run without system mode and auto-detect ALSA devices
RUN mkdir -p /etc/pulse \
    && echo "load-module module-native-protocol-unix" > /etc/pulse/default.pa \
    && echo "load-module module-detect" >> /etc/pulse/default.pa \
    && echo "load-module module-always-sink" >> /etc/pulse/default.pa \
    && echo "exit-idle-time = -1" > /etc/pulse/daemon.conf \
    && echo "flat-volumes = no" >> /etc/pulse/daemon.conf

WORKDIR /app

# Clone repository at specific version (branch, tag, or commit SHA)
# For commit SHAs, we need to fetch without depth limit then checkout
# hadolint ignore=SC3010
RUN if echo "${VERSION}" | grep -qE '^[0-9a-f]{7,40}$'; then \
      git clone https://github.com/OHF-Voice/linux-voice-assistant.git . && \
      git checkout "${VERSION}"; \
    else \
      git clone --depth 1 --branch "${VERSION}" https://github.com/OHF-Voice/linux-voice-assistant.git .; \
    fi

# Install Python package
# hadolint ignore=DL3013
RUN pip install --no-cache-dir -e .

# Create volume mount points
# /config - Custom wake word models and configuration
# /data - Runtime persistent data (preferences, downloaded models)
RUN mkdir -p /config /data

# Copy entrypoint script
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

VOLUME ["/config", "/data"]

# ESPHome voice assistant default port
EXPOSE 6053

ENTRYPOINT ["/app/entrypoint.sh"]
# No default CMD - entrypoint handles all configuration via environment variables
# Pass --help to see usage: docker run <image> --help
