#!/usr/bin/env bash
#
# Wyoming Satellite Entrypoint
#
# Environment variables:
#   SATELLITE_NAME      - Name of the satellite (default: "Wyoming Satellite")
#   SATELLITE_URI       - Wyoming server URI (default: tcp://0.0.0.0:10700)
#   MIC_DEVICE          - ALSA microphone device (default: sysdefault)
#   SND_DEVICE          - ALSA speaker device (default: sysdefault)
#   MIC_COMMAND         - Custom microphone command (overrides MIC_DEVICE)
#   SND_COMMAND         - Custom speaker command (overrides SND_DEVICE)
#   WAKE_URI            - Wake word service URI (optional)
#   WAKE_WORD           - Wake word name (optional)
#   VAD_ENABLED         - Enable voice activity detection (true/false)
#   NOISE_SUPPRESSION   - Noise suppression level 0-4 (optional)
#   AUTO_GAIN           - Auto gain control level 0-31 (optional)
#   DEBUG               - Enable debug logging (true/false)
#
set -e

# Default values
: "${SATELLITE_NAME:=Wyoming Satellite}"
: "${SATELLITE_URI:=tcp://0.0.0.0:10700}"
: "${MIC_DEVICE:=sysdefault}"
: "${SND_DEVICE:=sysdefault}"

# Build command arguments
ARGS=()

# Required: Server URI and name
ARGS+=("--uri" "${SATELLITE_URI}")
ARGS+=("--name" "${SATELLITE_NAME}")

# Microphone configuration
if [[ -n "${MIC_COMMAND}" ]]; then
    ARGS+=("--mic-command" "${MIC_COMMAND}")
elif [[ -n "${MIC_DEVICE}" ]]; then
    ARGS+=("--mic-command" "arecord -D ${MIC_DEVICE} -r 16000 -c 1 -f S16_LE -t raw")
fi

# Speaker configuration
if [[ -n "${SND_COMMAND}" ]]; then
    ARGS+=("--snd-command" "${SND_COMMAND}")
elif [[ -n "${SND_DEVICE}" ]]; then
    ARGS+=("--snd-command" "aplay -D ${SND_DEVICE} -r 22050 -c 1 -f S16_LE -t raw")
fi

# Wake word configuration
if [[ -n "${WAKE_URI}" ]]; then
    ARGS+=("--wake-uri" "${WAKE_URI}")
fi
if [[ -n "${WAKE_WORD}" ]]; then
    ARGS+=("--wake-word-name" "${WAKE_WORD}")
fi

# Voice activity detection
if [[ "${VAD_ENABLED}" == "true" ]]; then
    ARGS+=("--vad")
fi

# Audio processing
if [[ -n "${NOISE_SUPPRESSION}" ]]; then
    ARGS+=("--mic-noise-suppression" "${NOISE_SUPPRESSION}")
fi
if [[ -n "${AUTO_GAIN}" ]]; then
    ARGS+=("--mic-auto-gain" "${AUTO_GAIN}")
fi

# Custom sounds from /config
if [[ -f "/config/awake.wav" ]]; then
    ARGS+=("--awake-wav" "/config/awake.wav")
fi
if [[ -f "/config/done.wav" ]]; then
    ARGS+=("--done-wav" "/config/done.wav")
fi

# Debug mode
if [[ "${DEBUG}" == "true" ]]; then
    ARGS+=("--debug")
fi

# Handle command line arguments
if [[ $# -gt 0 ]]; then
    # Check for help first
    if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        exec python3 -m wyoming_satellite --help
    elif [[ "$1" == "--"* ]]; then
        # User is passing additional flags - append them
        ARGS+=("$@")
    else
        # User wants to run a different command entirely
        exec "$@"
    fi
fi

echo "Starting Wyoming Satellite: ${SATELLITE_NAME}"
echo "URI: ${SATELLITE_URI}"
if [[ "${DEBUG}" == "true" ]]; then
    echo "Arguments: ${ARGS[*]}"
fi

exec python3 -m wyoming_satellite "${ARGS[@]}"
