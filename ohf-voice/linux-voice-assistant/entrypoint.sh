#!/usr/bin/env bash
#
# Linux Voice Assistant Entrypoint
#
# Environment variables:
#   DEVICE_NAME         - Name shown in Home Assistant (required)
#   HOST                - ESPHome server bind address (default: 0.0.0.0)
#   PORT                - ESPHome server port (default: 6053)
#   AUDIO_INPUT_DEVICE  - Soundcard name for microphone (use --list-input-devices to find)
#   AUDIO_OUTPUT_DEVICE - MPV speaker device name (use --list-output-devices to find)
#   WAKE_MODEL          - Active wake word model ID (default: okay_nabu)
#   STOP_MODEL          - Stop model ID (default: stop)
#   WAKE_WORD_DIR       - Directory with custom wake word models
#   WAKEUP_SOUND        - Path to wake word trigger sound
#   PREFERENCES_FILE    - Path to preferences JSON file
#   DEBUG               - Enable debug logging (true/false)
#   PULSE_SERVER        - External PulseAudio server (skips internal PulseAudio startup)
#
set -e

# Start PulseAudio if not connecting to external server
start_pulseaudio() {
    # Skip if connecting to external PulseAudio
    if [[ -n "${PULSE_SERVER}" ]]; then
        echo "Using external PulseAudio server: ${PULSE_SERVER}"
        return 0
    fi

    # Check if PulseAudio is already running
    if pulseaudio --check 2>/dev/null; then
        echo "PulseAudio already running"
        return 0
    fi

    echo "Starting PulseAudio daemon..."
    # Start PulseAudio in background, allowing exit on idle to be disabled
    pulseaudio --start --log-target=stderr --exit-idle-time=-1 2>&1 || {
        echo "WARNING: Failed to start PulseAudio, audio may not work"
        return 0
    }

    # Wait for PulseAudio to be ready
    local retries=10
    while ! pulseaudio --check 2>/dev/null && [[ $retries -gt 0 ]]; do
        sleep 0.5
        retries=$((retries - 1))
    done

    if pulseaudio --check 2>/dev/null; then
        echo "PulseAudio started successfully"
    else
        echo "WARNING: PulseAudio may not be fully ready"
    fi
}

# Default values
: "${HOST:=0.0.0.0}"
: "${PORT:=6053}"
: "${WAKE_MODEL:=okay_nabu}"
: "${STOP_MODEL:=stop}"

# Build command arguments
ARGS=()

# Required: Device name
if [[ -n "${DEVICE_NAME}" ]]; then
    ARGS+=("--name" "${DEVICE_NAME}")
else
    # Check if user is just asking for help or listing devices
    if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        exec python3 -m linux_voice_assistant "$@"
    fi
    # Listing devices requires PulseAudio
    if [[ "$1" == "--list-input-devices" ]] || [[ "$1" == "--list-output-devices" ]]; then
        start_pulseaudio
        exec python3 -m linux_voice_assistant "$@"
    fi
    echo "ERROR: DEVICE_NAME environment variable is required"
    echo "Example: docker run -e DEVICE_NAME='Living Room' ..."
    echo ""
    echo "To list available audio devices, run:"
    echo "  docker run --rm <image> --list-input-devices"
    echo "  docker run --rm <image> --list-output-devices"
    exit 1
fi

# Server configuration
ARGS+=("--host" "${HOST}")
ARGS+=("--port" "${PORT}")

# Audio device configuration
if [[ -n "${AUDIO_INPUT_DEVICE}" ]]; then
    ARGS+=("--audio-input-device" "${AUDIO_INPUT_DEVICE}")
fi
if [[ -n "${AUDIO_OUTPUT_DEVICE}" ]]; then
    ARGS+=("--audio-output-device" "${AUDIO_OUTPUT_DEVICE}")
fi

# Wake word configuration
ARGS+=("--wake-model" "${WAKE_MODEL}")
ARGS+=("--stop-model" "${STOP_MODEL}")

# Custom wake word directory (from /config volume or custom path)
if [[ -n "${WAKE_WORD_DIR}" ]]; then
    ARGS+=("--wake-word-dir" "${WAKE_WORD_DIR}")
elif [[ -d "/config/wakewords" ]]; then
    ARGS+=("--wake-word-dir" "/config/wakewords")
fi

# Download directory for models
ARGS+=("--download-dir" "/data/downloads")

# Custom sounds
if [[ -n "${WAKEUP_SOUND}" ]]; then
    ARGS+=("--wakeup-sound" "${WAKEUP_SOUND}")
elif [[ -f "/config/wakeup.flac" ]]; then
    ARGS+=("--wakeup-sound" "/config/wakeup.flac")
fi

# Preferences file
if [[ -n "${PREFERENCES_FILE}" ]]; then
    ARGS+=("--preferences-file" "${PREFERENCES_FILE}")
else
    ARGS+=("--preferences-file" "/data/preferences.json")
fi

# Debug mode
if [[ "${DEBUG}" == "true" ]]; then
    ARGS+=("--debug")
fi

# Handle command line arguments
if [[ $# -gt 0 ]]; then
    # Check for help first (doesn't need PulseAudio)
    if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        exec python3 -m linux_voice_assistant "$@"
    # Device listing needs PulseAudio
    elif [[ "$1" == "--list-input-devices" ]] || [[ "$1" == "--list-output-devices" ]]; then
        start_pulseaudio
        exec python3 -m linux_voice_assistant "$@"
    elif [[ "$1" == "--"* ]]; then
        # User is passing additional flags - append them
        ARGS+=("$@")
    else
        # User wants to run a different command entirely
        exec "$@"
    fi
fi

# Start PulseAudio (required by soundcard library for ALSA access)
start_pulseaudio

echo "Starting Linux Voice Assistant: ${DEVICE_NAME}"
echo "ESPHome server: ${HOST}:${PORT}"
echo "Wake model: ${WAKE_MODEL}"
if [[ "${DEBUG}" == "true" ]]; then
    echo "Arguments: ${ARGS[*]}"
fi

exec python3 -m linux_voice_assistant "${ARGS[@]}"
