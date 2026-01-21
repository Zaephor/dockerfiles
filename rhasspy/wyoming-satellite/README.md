# Wyoming Satellite

Remote voice satellite using the [Wyoming protocol](https://github.com/rhasspy/wyoming) for Home Assistant voice assistants.

> **Note:** This project is deprecated by upstream in favor of [linux-voice-assistant](https://github.com/OHF-Voice/linux-voice-assistant) which uses the ESPHome protocol. However, it remains useful for Wyoming protocol-based setups.

## Upstream Project

- **Repository:** https://github.com/rhasspy/wyoming-satellite
- **Protocol:** Wyoming (TCP-based)
- **Default Port:** 10700

## Audio Device Access

The container requires access to your host's audio devices via ALSA.

### Finding Your Audio Device

```bash
# On the host, list available devices
arecord -L  # Capture devices (microphones)
aplay -L    # Playback devices (speakers)

# Common device names:
# - default          - System default
# - sysdefault       - System default (explicit)
# - plughw:0,0       - First sound card
# - plughw:1,0       - Second sound card (often USB)
# - hw:CARD=Device   - By card name
```

---

## Docker

### Basic Usage

```bash
docker run -d \
  --name wyoming-satellite \
  --device /dev/snd:/dev/snd \
  --group-add audio \
  -e SATELLITE_NAME="Living Room" \
  -e MIC_DEVICE="plughw:1,0" \
  -e SND_DEVICE="plughw:1,0" \
  -p 10700:10700 \
  ghcr.io/your-org/wyoming-satellite:latest
```

### With Wake Word Service

```bash
docker run -d \
  --name wyoming-satellite \
  --device /dev/snd:/dev/snd \
  --group-add audio \
  -e SATELLITE_NAME="Kitchen" \
  -e MIC_DEVICE="plughw:1,0" \
  -e SND_DEVICE="plughw:1,0" \
  -e WAKE_URI="tcp://192.168.1.100:10400" \
  -e WAKE_WORD="ok_nabu" \
  -e VAD_ENABLED="true" \
  -e NOISE_SUPPRESSION="2" \
  -p 10700:10700 \
  -v ./config:/config:ro \
  -v ./data:/data \
  ghcr.io/your-org/wyoming-satellite:latest
```

### Custom Audio Commands

```bash
docker run -d \
  --name wyoming-satellite \
  --device /dev/snd:/dev/snd \
  --group-add audio \
  -e SATELLITE_NAME="Office" \
  -e MIC_COMMAND="arecord -D plughw:2,0 -r 16000 -c 1 -f S16_LE -t raw" \
  -e SND_COMMAND="aplay -D plughw:2,0 -r 22050 -c 1 -f S16_LE -t raw" \
  -p 10700:10700 \
  ghcr.io/your-org/wyoming-satellite:latest
```

---

## Docker Compose

### Basic Setup

```yaml
version: "3.8"

services:
  wyoming-satellite:
    image: ghcr.io/your-org/wyoming-satellite:latest
    container_name: wyoming-satellite
    restart: unless-stopped
    devices:
      - /dev/snd:/dev/snd
    group_add:
      - audio
    ports:
      - "10700:10700"
    environment:
      SATELLITE_NAME: "Living Room"
      MIC_DEVICE: "plughw:1,0"
      SND_DEVICE: "plughw:1,0"
      DEBUG: "false"
    volumes:
      - ./config:/config:ro
      - ./data:/data
```

### With Local Wake Word Detection

```yaml
version: "3.8"

services:
  wyoming-satellite:
    image: ghcr.io/your-org/wyoming-satellite:latest
    container_name: wyoming-satellite
    restart: unless-stopped
    depends_on:
      - openwakeword
    devices:
      - /dev/snd:/dev/snd
    group_add:
      - audio
    ports:
      - "10700:10700"
    environment:
      SATELLITE_NAME: "Kitchen Satellite"
      MIC_DEVICE: "plughw:1,0"
      SND_DEVICE: "plughw:1,0"
      WAKE_URI: "tcp://openwakeword:10400"
      WAKE_WORD: "ok_nabu"
      VAD_ENABLED: "true"
      NOISE_SUPPRESSION: "2"
      AUTO_GAIN: "15"
      DEBUG: "false"
    volumes:
      - ./config:/config:ro
      - ./data:/data

  openwakeword:
    image: rhasspy/wyoming-openwakeword:latest
    container_name: openwakeword
    restart: unless-stopped
    ports:
      - "10400:10400"
    command:
      - --preload-model
      - ok_nabu
```

---

## Podman Quadlet

Create the following files in `~/.config/containers/systemd/` (user) or `/etc/containers/systemd/` (system).

### wyoming-satellite.container

```ini
[Unit]
Description=Wyoming Satellite Voice Assistant
After=network-online.target

[Container]
Image=ghcr.io/your-org/wyoming-satellite:latest
ContainerName=wyoming-satellite
AutoUpdate=registry

# Audio device access
AddDevice=/dev/snd:/dev/snd
Group=audio

# Network
PublishPort=10700:10700

# Environment
Environment=SATELLITE_NAME="Living Room"
Environment=MIC_DEVICE=plughw:1,0
Environment=SND_DEVICE=plughw:1,0
Environment=DEBUG=false

# Volumes
Volume=wyoming-satellite-config:/config:ro
Volume=wyoming-satellite-data:/data

[Service]
Restart=on-failure
TimeoutStartSec=300

[Install]
WantedBy=default.target
```

### With Wake Word Service

**openwakeword.container:**

```ini
[Unit]
Description=OpenWakeWord Service
After=network-online.target

[Container]
Image=docker.io/rhasspy/wyoming-openwakeword:latest
ContainerName=openwakeword
AutoUpdate=registry

PublishPort=10400:10400
Exec=--preload-model ok_nabu

[Service]
Restart=on-failure

[Install]
WantedBy=default.target
```

**wyoming-satellite.container:** (with wake word)

```ini
[Unit]
Description=Wyoming Satellite Voice Assistant
After=network-online.target openwakeword.service
Requires=openwakeword.service

[Container]
Image=ghcr.io/your-org/wyoming-satellite:latest
ContainerName=wyoming-satellite
AutoUpdate=registry

AddDevice=/dev/snd:/dev/snd
Group=audio

PublishPort=10700:10700
Network=host

Environment=SATELLITE_NAME="Kitchen"
Environment=MIC_DEVICE=plughw:1,0
Environment=SND_DEVICE=plughw:1,0
Environment=WAKE_URI=tcp://127.0.0.1:10400
Environment=WAKE_WORD=ok_nabu
Environment=VAD_ENABLED=true
Environment=NOISE_SUPPRESSION=2
Environment=DEBUG=false

Volume=wyoming-satellite-config:/config:ro
Volume=wyoming-satellite-data:/data

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
systemctl --user start wyoming-satellite

# Enable at boot
systemctl --user enable wyoming-satellite

# Check status
systemctl --user status wyoming-satellite

# View logs
journalctl --user -u wyoming-satellite -f
```

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SATELLITE_NAME` | `Wyoming Satellite` | Name shown in Home Assistant |
| `SATELLITE_URI` | `tcp://0.0.0.0:10700` | Wyoming server bind address |
| `MIC_DEVICE` | `sysdefault` | ALSA microphone device |
| `SND_DEVICE` | `sysdefault` | ALSA speaker device |
| `MIC_COMMAND` | *(auto)* | Custom mic command (overrides MIC_DEVICE) |
| `SND_COMMAND` | *(auto)* | Custom speaker command (overrides SND_DEVICE) |
| `WAKE_URI` | - | Wake word service URI (e.g., `tcp://openwakeword:10400`) |
| `WAKE_WORD` | - | Wake word name (e.g., `ok_nabu`) |
| `VAD_ENABLED` | `false` | Enable voice activity detection |
| `NOISE_SUPPRESSION` | - | Noise suppression level (0-4) |
| `AUTO_GAIN` | - | Auto gain control level (0-31) |
| `DEBUG` | `false` | Enable debug logging |

## Volume Mounts

| Path | Purpose |
|------|---------|
| `/config` | Custom sound files (`awake.wav`, `done.wav`) |
| `/data` | Wake word models and runtime data |

---

## Home Assistant Integration

1. Go to **Settings** > **Devices & Services** > **Add Integration**
2. Search for **Wyoming Protocol**
3. Enter the satellite's IP address and port (10700)
4. The satellite will appear as a voice assistant device

---

## Architecture Support

- `linux/amd64`
- `linux/arm64`

---

## Troubleshooting

### No audio capture

```bash
# Verify device access inside container
docker exec wyoming-satellite arecord -l

# Test recording
docker exec wyoming-satellite arecord -D plughw:1,0 -d 5 -f S16_LE -r 16000 /tmp/test.wav
```

### Connection refused

1. Verify the port is exposed: `-p 10700:10700`
2. Check firewall rules allow TCP 10700
3. Use `--network host` if discovery issues persist

### Debug mode

```bash
docker run -e DEBUG=true ...
# or
docker logs -f wyoming-satellite
```

---

## License

This container packages the upstream [wyoming-satellite](https://github.com/rhasspy/wyoming-satellite) project, which is licensed under the MIT License.
