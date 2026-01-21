# Wyoming Satellite - Remote voice satellite for Home Assistant
# https://github.com/rhasspy/wyoming-satellite
#
# NOTE: This project is deprecated in favor of linux-voice-assistant,
# but remains useful for Wyoming protocol-based setups.

FROM python:3.11-slim-bookworm

ARG VERSION=master

ENV LANG=C.UTF-8
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
# - avahi-utils: mDNS service discovery
# - alsa-utils: ALSA audio tools (arecord, aplay)
# - pulseaudio-utils: PulseAudio tools (optional, for parecord/paplay)
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    avahi-utils \
    alsa-utils \
    pulseaudio-utils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Clone repository at specific commit
RUN git clone --depth 1 https://github.com/rhasspy/wyoming-satellite.git . \
    && git fetch --depth 1 origin "${VERSION}" \
    && git checkout "${VERSION}"

# Install with all optional dependencies (VAD, noise suppression)
# hadolint ignore=DL3013
RUN pip install --no-cache-dir --extra-index-url https://www.piwheels.org/simple \
    -e '.[all]'

# Create volume mount points
# /config - Custom configuration and sound files
# /data - Wake word models and runtime data
RUN mkdir -p /config /data

# Copy entrypoint script
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

VOLUME ["/config", "/data"]

# Wyoming protocol default port
EXPOSE 10700

ENTRYPOINT ["/app/entrypoint.sh"]
# No default CMD - entrypoint handles all configuration via environment variables
# Pass --help to see usage: docker run <image> --help
