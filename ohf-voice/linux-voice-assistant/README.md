# Linux Voice Assistant

Voice satellite using the ESPHome protocol for Home Assistant voice assistants. This is the successor to [wyoming-satellite](https://github.com/rhasspy/wyoming-satellite) and provides native ESPHome integration.

## Upstream Project

- **Repository:** https://github.com/OHF-Voice/linux-voice-assistant
- **Protocol:** ESPHome Voice Assistant
- **Default Port:** 6053

> **Note:** The upstream project is under active development and may occasionally have build issues. If the container fails to build, check the upstream repository for recent fixes.

## Audio Architecture

This container uses PulseAudio internally to interface with ALSA audio devices. The `soundcard` library requires PulseAudio, so the container automatically starts a PulseAudio daemon that connects to your ALSA hardware.

**Supported configurations:**
- Direct ALSA device access (PulseAudio started internally)
- External PulseAudio/PipeWire server on host

## Audio Device Access

### Finding Your Audio Device

```bash
# On the host, list ALSA devices
arecord -L  # Capture devices (microphones)
aplay -L    # Playback devices (speakers)

# Inside container (requires audio device mounted)
docker run --rm --device /dev/snd \
  ghcr.io/zaephor/dockerfiles/ohf-voice/linux-voice-assistant:dev \
  --list-input-devices

docker run --rm --device /dev/snd \
  ghcr.io/zaephor/dockerfiles/ohf-voice/linux-voice-assistant:dev \
  --list-output-devices
```

---

## Docker

### Basic Usage (ALSA)

```bash
docker run -d \
  --name linux-voice-assistant \
  --device /dev/snd:/dev/snd \
  --group-add audio \
  -e DEVICE_NAME="Living Room" \
  -p 6053:6053 \
  ghcr.io/zaephor/dockerfiles/ohf-voice/linux-voice-assistant:dev
```

### With Specific Audio Devices

```bash
docker run -d \
  --name linux-voice-assistant \
  --device /dev/snd:/dev/snd \
  --group-add audio \
  -e DEVICE_NAME="Kitchen" \
  -e AUDIO_INPUT_DEVICE="USB Audio Device" \
  -e AUDIO_OUTPUT_DEVICE="pulse" \
  -e WAKE_MODEL="okay_nabu" \
  -p 6053:6053 \
  -v ./config:/config:ro \
  -v ./data:/data \
  ghcr.io/zaephor/dockerfiles/ohf-voice/linux-voice-assistant:dev
```

### With External PulseAudio (Host)

```bash
docker run -d \
  --name linux-voice-assistant \
  -v /run/user/1000/pulse:/run/user/1000/pulse \
  -e PULSE_SERVER=unix:/run/user/1000/pulse/native \
  -e DEVICE_NAME="Office" \
  -p 6053:6053 \
  ghcr.io/zaephor/dockerfiles/ohf-voice/linux-voice-assistant:dev
```

### With Custom Wake Word Models

```bash
docker run -d \
  --name linux-voice-assistant \
  --device /dev/snd:/dev/snd \
  --group-add audio \
  -e DEVICE_NAME="Bedroom" \
  -e WAKE_MODEL="my_custom_word" \
  -e WAKE_WORD_DIR="/config/wakewords" \
  -p 6053:6053 \
  -v ./wakewords:/config/wakewords:ro \
  -v ./data:/data \
  ghcr.io/zaephor/dockerfiles/ohf-voice/linux-voice-assistant:dev
```

---

## Docker Compose

### Basic Setup (ALSA)

```yaml
version: "3.8"

services:
  linux-voice-assistant:
    image: ghcr.io/zaephor/dockerfiles/ohf-voice/linux-voice-assistant:dev
    container_name: linux-voice-assistant
    restart: unless-stopped
    devices:
      - /dev/snd:/dev/snd
    group_add:
      - audio
    ports:
      - "6053:6053"
    environment:
      DEVICE_NAME: "Living Room"
      WAKE_MODEL: "okay_nabu"
      DEBUG: "false"
    volumes:
      - ./config:/config:ro
      - ./data:/data
```

### With External PulseAudio

```yaml
version: "3.8"

services:
  linux-voice-assistant:
    image: ghcr.io/zaephor/dockerfiles/ohf-voice/linux-voice-assistant:dev
    container_name: linux-voice-assistant
    restart: unless-stopped
    ports:
      - "6053:6053"
    environment:
      PULSE_SERVER: "unix:/run/user/1000/pulse/native"
      DEVICE_NAME: "Kitchen"
      WAKE_MODEL: "okay_nabu"
      DEBUG: "false"
    volumes:
      - /run/user/1000/pulse:/run/user/1000/pulse
      - ./config:/config:ro
      - ./data:/data
```

### Full Featured Setup

```yaml
version: "3.8"

services:
  linux-voice-assistant:
    image: ghcr.io/zaephor/dockerfiles/ohf-voice/linux-voice-assistant:dev
    container_name: linux-voice-assistant
    restart: unless-stopped
    devices:
      - /dev/snd:/dev/snd
    group_add:
      - audio
    ports:
      - "6053:6053"
    environment:
      DEVICE_NAME: "Office Voice"
      AUDIO_INPUT_DEVICE: "USB Audio Device"
      WAKE_MODEL: "okay_nabu"
      STOP_MODEL: "stop"
      DEBUG: "false"
    volumes:
      - ./config:/config:ro
      - ./data:/data
    healthcheck:
      test: ["CMD", "python3", "-c", "import socket; s=socket.socket(); s.connect(('127.0.0.1', 6053)); s.close()"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
```

---

## Podman Quadlet

Create the following files in `~/.config/containers/systemd/` (user) or `/etc/containers/systemd/` (system).

### linux-voice-assistant.container (ALSA)

```ini
[Unit]
Description=Linux Voice Assistant
After=network-online.target sound.target

[Container]
Image=ghcr.io/zaephor/dockerfiles/ohf-voice/linux-voice-assistant:dev
ContainerName=linux-voice-assistant
AutoUpdate=registry

# Audio device access
AddDevice=/dev/snd:/dev/snd
AddGroup=audio

# Network
PublishPort=6053:6053

# Environment
Environment=DEVICE_NAME="Living Room"
Environment=WAKE_MODEL=okay_nabu
Environment=DEBUG=false

# Volumes
Volume=linux-voice-assistant-config:/config:ro
Volume=linux-voice-assistant-data:/data

[Service]
Restart=on-failure
TimeoutStartSec=300

[Install]
WantedBy=default.target
```

### linux-voice-assistant.container (External PulseAudio)

```ini
[Unit]
Description=Linux Voice Assistant
After=network-online.target pulseaudio.service

[Container]
Image=ghcr.io/zaephor/dockerfiles/ohf-voice/linux-voice-assistant:dev
ContainerName=linux-voice-assistant
AutoUpdate=registry

# Network
PublishPort=6053:6053

# Environment
Environment=PULSE_SERVER=unix:/run/user/1000/pulse/native
Environment=DEVICE_NAME="Kitchen"
Environment=WAKE_MODEL=okay_nabu
Environment=DEBUG=false

# Volumes - PulseAudio socket
Volume=/run/user/1000/pulse:/run/user/1000/pulse
Volume=linux-voice-assistant-config:/config:ro
Volume=linux-voice-assistant-data:/data

[Service]
Restart=on-failure
TimeoutStartSec=300

[Install]
WantedBy=default.target
```

### With Specific Audio Device

```ini
[Unit]
Description=Linux Voice Assistant
After=network-online.target sound.target

[Container]
Image=ghcr.io/zaephor/dockerfiles/ohf-voice/linux-voice-assistant:dev
ContainerName=linux-voice-assistant
AutoUpdate=registry

AddDevice=/dev/snd:/dev/snd
AddGroup=audio

PublishPort=6053:6053

Environment=DEVICE_NAME="Office"
Environment=AUDIO_INPUT_DEVICE="USB Audio Device"
Environment=WAKE_MODEL=okay_nabu
Environment=STOP_MODEL=stop
Environment=DEBUG=false

Volume=linux-voice-assistant-config:/config:ro
Volume=linux-voice-assistant-data:/data

[Service]
Restart=on-failure
TimeoutStartSec=300

[Install]
WantedBy=default.target
```

### Enable and Start

```bash
# Reload systemd to pick up quadlet files
systemctl --user daemon-reload

# Start the service
systemctl --user start linux-voice-assistant

# Enable at boot
systemctl --user enable linux-voice-assistant

# Check status
systemctl --user status linux-voice-assistant

# View logs
journalctl --user -u linux-voice-assistant -f
```

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DEVICE_NAME` | *(required)* | Name shown in Home Assistant |
| `HOST` | `0.0.0.0` | ESPHome server bind address |
| `PORT` | `6053` | ESPHome server port |
| `AUDIO_INPUT_DEVICE` | *(auto)* | Soundcard name for microphone |
| `AUDIO_OUTPUT_DEVICE` | *(auto)* | MPV speaker device name |
| `WAKE_MODEL` | `okay_nabu` | Active wake word model ID |
| `STOP_MODEL` | `stop` | Stop listening model ID |
| `WAKE_WORD_DIR` | - | Directory with custom wake word models |
| `WAKEUP_SOUND` | - | Path to wake word trigger sound |
| `PREFERENCES_FILE` | `/data/preferences.json` | Path to preferences JSON |
| `PULSE_SERVER` | - | External PulseAudio server (skips internal startup) |
| `DEBUG` | `false` | Enable debug logging |

## Volume Mounts

| Path | Purpose |
|------|---------|
| `/config` | Custom wake word models and sounds |
| `/config/wakewords/` | Custom `.tflite` wake word models with `.json` configs |
| `/config/wakeup.flac` | Custom wake word trigger sound |
| `/data` | Persistent runtime data |
| `/data/preferences.json` | User preferences (auto-generated) |
| `/data/downloads/` | Downloaded wake word models |

---

## Wake Word Models

The container includes default wake word models:
- `okay_nabu` - "Okay Nabu" trigger phrase
- `stop` - "Stop" to cancel listening

### Custom Wake Word Models

1. Create a directory with your `.tflite` model and `.json` config:

```
wakewords/
├── my_word.tflite
└── my_word.json
```

2. Mount it and configure:

```bash
docker run -d \
  -v ./wakewords:/config/wakewords:ro \
  -e WAKE_MODEL="my_word" \
  ...
```

---

## Home Assistant Integration

1. Go to **Settings** > **Devices & Services** > **Add Integration**
2. Search for **ESPHome**
3. Enter the container's IP address and port (6053)
4. The voice assistant will appear as a device

For automatic discovery, ensure Home Assistant and the voice assistant are on the same network segment.

---

## Architecture Support

- `linux/amd64`
- `linux/arm64`

---

## Troubleshooting

### Container fails to start

The container requires PulseAudio. If using ALSA directly, ensure `/dev/snd` is mounted:

```bash
docker run --device /dev/snd --group-add audio ...
```

### No audio input detected

```bash
# List available devices
docker run --rm --device /dev/snd \
  ghcr.io/zaephor/dockerfiles/ohf-voice/linux-voice-assistant:dev \
  --list-input-devices

# Check PulseAudio inside container
docker exec linux-voice-assistant pactl info
```

### Audio playback issues

```bash
# List output devices
docker run --rm --device /dev/snd \
  ghcr.io/zaephor/dockerfiles/ohf-voice/linux-voice-assistant:dev \
  --list-output-devices
```

### Home Assistant can't find device

1. Verify port 6053 is accessible
2. Check container logs: `docker logs linux-voice-assistant`
3. Enable debug: `-e DEBUG=true`

### Wake word not triggering

1. Check microphone is working (enable DEBUG mode)
2. Try default wake word model first
3. Verify audio input levels

### Debug mode

```bash
docker run -e DEBUG=true ...
# or
docker logs -f linux-voice-assistant
```

---

## License

This container packages the upstream [linux-voice-assistant](https://github.com/OHF-Voice/linux-voice-assistant) project, which is licensed under the Apache License 2.0.
