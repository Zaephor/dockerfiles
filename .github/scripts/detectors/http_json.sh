#!/usr/bin/env bash
#
# HTTP API Version Detector
#
# Detects versions by fetching from a custom HTTP endpoint and parsing
# the response using JSONPath (for JSON) or XPath (for XML).
#
# Usage:
#   ./http-api.sh --config /path/to/metadata.yaml --image-name image-name
#
# Configuration (metadata.yaml):
#   version_source:
#     type: http-api
#     url: https://api.example.com/releases/latest  # Required: endpoint URL
#     format: json  # Required: response format (json or xml)
#     path: $.version  # Required: JSONPath (json) or XPath (xml)
#     headers:  # Optional: custom HTTP headers
#       User-Agent: 'custom-user-agent'
#       Authorization: 'Bearer ${API_TOKEN}'  # Environment variable expansion
#

set -euo pipefail

# Script directory (for sourcing libraries)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Source libraries
source "${LIB_DIR}/cache.sh" || {
  echo "ERROR: Failed to source cache library" >&2
  exit 2
}

source "${LIB_DIR}/version-parser.sh" || {
  echo "ERROR: Failed to source version parser library" >&2
  exit 2
}

readonly DETECTOR_NAME="http-api"

# ============================================================================
# Standard JSON Output Functions
# ============================================================================

output_success() {
  local version="$1"
  local detector="$2"
  local cached="${3:-false}"
  local source_url="${4:-}"

  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  cat <<EOF
{
  "version": "${version}",
  "status": "success",
  "detector": "${detector}",
  "cached": ${cached},
  "metadata": {
    "source_url": "${source_url}",
    "detected_at": "${timestamp}"
  }
}
EOF
}

output_error() {
  local error_code="$1"
  local error_message="$2"
  local detector="${3:-unknown}"

  cat <<EOF
{
  "version": null,
  "status": "failure",
  "detector": "${detector}",
  "error": "${error_message}",
  "error_code": "${error_code}"
}
EOF
}

# ============================================================================
# Configuration Parsing
# ============================================================================

# Parse HTTP API configuration from metadata.yaml
#
# Arguments:
#   $1: Path to metadata.yaml
#
# Output:
#   url, format, path, headers_json (one per line)
#
# Returns:
#   0 on success, 2 on config error
#
parse_http_config() {
  local config_file="$1"

  if [[ ! -f "$config_file" ]]; then
    output_error "CONFIG_ERROR" "Config file not found: $config_file" "$DETECTOR_NAME"
    return 2
  fi

  # Extract URL
  local url
  url=$(yq eval '.version_source.url' "$config_file" 2>/dev/null) || {
    output_error "CONFIG_ERROR" "Failed to parse version_source from $config_file" "$DETECTOR_NAME"
    return 2
  }

  if [[ -z "$url" || "$url" == "null" ]]; then
    output_error "CONFIG_ERROR" "Missing required field: version_source.url" "$DETECTOR_NAME"
    return 2
  fi

  # Extract format (json or xml)
  local format
  format=$(yq eval '.version_source.format' "$config_file" 2>/dev/null) || {
    output_error "CONFIG_ERROR" "Failed to parse format from $config_file" "$DETECTOR_NAME"
    return 2
  }

  if [[ -z "$format" || "$format" == "null" ]]; then
    output_error "CONFIG_ERROR" "Missing required field: version_source.format" "$DETECTOR_NAME"
    return 2
  fi

  if [[ "$format" != "json" && "$format" != "xml" ]]; then
    output_error "CONFIG_ERROR" "Invalid format: $format (must be json or xml)" "$DETECTOR_NAME"
    return 2
  fi

  # Extract path (JSONPath or XPath)
  local path
  path=$(yq eval '.version_source.path' "$config_file" 2>/dev/null) || {
    output_error "CONFIG_ERROR" "Failed to parse path from $config_file" "$DETECTOR_NAME"
    return 2
  }

  if [[ -z "$path" || "$path" == "null" ]]; then
    output_error "CONFIG_ERROR" "Missing required field: version_source.path" "$DETECTOR_NAME"
    return 2
  fi

  # Extract optional headers (as JSON)
  local headers_json
  headers_json=$(yq eval '.version_source.headers' "$config_file" 2>/dev/null || echo "{}")
  [[ "$headers_json" == "null" ]] && headers_json="{}"

  # Output parsed values
  echo "$url"
  echo "$format"
  echo "$path"
  echo "$headers_json"

  return 0
}

# ============================================================================
# HTTP Request Handling
# ============================================================================

# Expand environment variables in string
#
# Arguments:
#   $1: String potentially containing ${VAR} references
#
# Output:
#   String with environment variables expanded
#
expand_env_vars() {
  local str="$1"
  # Use eval to expand environment variables
  eval echo "$str"
}

# Build curl headers from headers JSON
#
# Arguments:
#   $1: Headers JSON (from metadata.yaml)
#
# Output:
#   Array of curl header arguments (--header "Name: Value")
#
build_curl_headers() {
  local headers_json="$1"

  # Parse headers using jq and convert to curl arguments
  local headers=()
  while IFS= read -r header; do
    if [[ -n "$header" ]]; then
      headers+=("--header" "$header")
    fi
  done < <(echo "$headers_json" | jq -r 'to_entries[] | "\(.key): \(.value)"' 2>/dev/null || true)

  # Expand environment variables in each header
  local expanded_headers=()
  for ((i = 0; i < ${#headers[@]}; i += 2)); do
    local key="${headers[$i]}"
    local value="${headers[$((i+1))]}"
    value=$(expand_env_vars "$value")
    expanded_headers+=("$key" "$value")
  done

  # Output headers in curl format
  printf '%s\n' "${expanded_headers[@]}"
}

# Fetch from HTTP endpoint
#
# Arguments:
#   $1: URL
#   $2: Headers array (as strings from build_curl_headers)
#
# Output:
#   Response body
#
# Returns:
#   0 on success, 1 on failure
#
fetch_http_endpoint() {
  local url="$1"
  shift
  local headers=("$@")

  echo "INFO: Fetching HTTP endpoint: $url" >&2

  # Fetch with timeout
  local response
  response=$(timeout 30s curl -s "${headers[@]}" "$url" 2>&1) || {
    local exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
      return 1  # Timeout
    fi
    return 1  # Network error
  }

  if [[ -z "$response" ]]; then
    return 1
  fi

  echo "$response"
  return 0
}

# ============================================================================
# Response Parsing
# ============================================================================

# Parse JSON response using JSONPath
#
# Arguments:
#   $1: JSON response
#   $2: JSONPath expression (e.g., $.version or $.data.latest.version)
#
# Output:
#   Extracted value
#
# Returns:
#   0 on success, 1 on parse failure
#
parse_json_response() {
  local response="$1"
  local jsonpath="$2"

  # Convert JSONPath to jq filter
  # Simple conversion: $.foo.bar -> .foo.bar
  local jq_filter="${jsonpath#$.}"
  [[ "$jq_filter" == "$jsonpath" ]] && jq_filter=".${jsonpath#$}"
  jq_filter=".${jq_filter}"

  echo "INFO: Parsing JSON with jq filter: $jq_filter" >&2

  local value
  value=$(echo "$response" | jq -r "$jq_filter" 2>/dev/null) || {
    echo "ERROR: Failed to parse JSON with jq" >&2
    return 1
  }

  if [[ -z "$value" || "$value" == "null" ]]; then
    echo "ERROR: JSONPath expression returned null or empty" >&2
    return 1
  fi

  echo "$value"
  return 0
}

# Parse XML response using XPath
#
# Arguments:
#   $1: XML response
#   $2: XPath expression
#
# Output:
#   Extracted value
#
# Returns:
#   0 on success, 1 on parse failure
#
parse_xml_response() {
  local response="$1"
  local xpath="$2"

  echo "INFO: Parsing XML with XPath: $xpath" >&2

  # Use yq for XML parsing
  local value
  value=$(echo "$response" | yq eval "$xpath" - 2>/dev/null) || {
    echo "ERROR: Failed to parse XML with yq" >&2
    return 1
  }

  if [[ -z "$value" || "$value" == "null" ]]; then
    echo "ERROR: XPath expression returned null or empty" >&2
    return 1
  fi

  echo "$value"
  return 0
}

# ============================================================================
# Detection Logic
# ============================================================================

# Perform version detection from HTTP API
#
# Arguments:
#   $1: Path to metadata.yaml
#   $2: Image name
#
# Output:
#   Version string on success, JSON error on failure
#
# Returns:
#   0 on success, 1 on failure, 2 on config error
#
detect_version() {
  local config_file="$1"
  local image_name="$2"

  # Parse configuration
  local config_output
  config_output=$(parse_http_config "$config_file") || return 2

  read -r url format path headers_json <<< "$config_output"

  echo "INFO: Detecting HTTP API version from: $url" >&2

  # Build curl headers
  local headers_str
  headers_str=$(build_curl_headers "$headers_json")

  # Convert headers string to array
  local headers_array=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && headers_array+=("$line")
  done <<< "$headers_str"

  # Fetch HTTP endpoint
  local response
  response=$(fetch_http_endpoint "$url" "${headers_array[@]}") || {
    output_error "NETWORK_ERROR" "Failed to fetch HTTP endpoint" "$DETECTOR_NAME"
    return 1
  }

  # Parse response based on format
  local version
  if [[ "$format" == "json" ]]; then
    version=$(parse_json_response "$response" "$path") || {
      output_error "PARSE_ERROR" "Failed to parse JSON response with JSONPath: $path" "$DETECTOR_NAME"
      return 1
    }
  elif [[ "$format" == "xml" ]]; then
    version=$(parse_xml_response "$response" "$path") || {
      output_error "PARSE_ERROR" "Failed to parse XML response with XPath: $path" "$DETECTOR_NAME"
      return 1
    }
  fi

  if [[ -z "$version" ]]; then
    output_error "PARSE_ERROR" "Failed to extract version from API response" "$DETECTOR_NAME"
    return 1
  fi

  # Generate source URL
  local source_url="$url"

  echo "$version"
  echo "$source_url"
  return 0
}

# ============================================================================
# Main Entry Point
# ============================================================================

# Parse command-line arguments
parse_arguments() {
  local config_file=""
  local image_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        config_file="$2"
        shift 2
        ;;
      --image-name)
        image_name="$2"
        shift 2
        ;;
      *)
        echo "ERROR: Unknown argument: $1" >&2
        return 1
        ;;
    esac
  done

  if [[ -z "$config_file" || -z "$image_name" ]]; then
    echo "ERROR: Missing required arguments: --config and --image-name" >&2
    return 1
  fi

  echo "$config_file" "$image_name"
  return 0
}

main() {
  # Parse arguments
  local args
  args=$(parse_arguments "$@") || {
    output_error "CONFIG_ERROR" "Invalid arguments: $*" "$DETECTOR_NAME"
    exit 2
  }

  read -r config_file image_name <<< "$args"

  echo "INFO: HTTP API detector starting for image: $image_name" >&2

  # Check cache first
  local cached_version
  if cached_version=$(get_cached_version "$image_name" 2>/dev/null); then
    echo "INFO: Using cached version for $image_name: $cached_version" >&2
    output_success "$cached_version" "$DETECTOR_NAME" true
    exit 0
  fi

  # Perform detection with timeout
  echo "INFO: Performing fresh detection for $image_name" >&2

  local version
  local source_url
  local output
  local exit_code

  # Invoke detection (timeout enforced by CI/CD environment, not shell wrapper)
  # Shell functions cannot be wrapped with 'timeout' command as timeout cannot
  # execute bash functions directly. CI/CD environments enforce timeouts at job level.
  # Note: Do NOT redirect stderr here - we want INFO logs on stderr, JSON output on stdout
  output=$(detect_version "$config_file" "$image_name") || {
    exit_code=$?
    if [[ $exit_code -eq 2 ]]; then
      # Fatal configuration error
      echo "$output"
      exit 2
    else
      # Detection failed
      echo "$output"
      exit 1
    fi
  }

  # Parse output (version and source URL)
  read -r version source_url <<< "$output"

  if [[ -z "$version" ]]; then
    echo "ERROR: Detection returned empty version" >&2
    output_error "PARSE_ERROR" "Detection returned empty version" "$DETECTOR_NAME"
    exit 1
  fi

  # Cache the result
  write_cache "$image_name" "$version" "$DETECTOR_NAME" "$source_url"

  # Output success
  output_success "$version" "$DETECTOR_NAME" false "$source_url"
  exit 0
}

# Run main function
main "$@"
