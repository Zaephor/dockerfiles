#!/usr/bin/env bash
# Image discovery library
# Discovers all Docker image directories (supports nested folders)
# Images are identified by presence of metadata.yaml and at least one Dockerfile
# (either default Dockerfile or any Dockerfile.* variant)

set -euo pipefail

# Discover all image directories in repository
# Discovers directories containing metadata.yaml and at least one Dockerfile
# (either default Dockerfile or any Dockerfile.* variant)
# Supports nested folders (e.g., traefik/traefik, traefik/whoami)
# Args:
#   $1: Repository root directory
# Returns:
#   Array of image directory paths relative to repo root (e.g., "hello-world", "traefik/traefik")
discover_images() {
    local repo_root="${1:-.}"
    local -a images=()

    # Excluded directories to skip during discovery
    local -a exclude_patterns=(
        ".github"
        ".git"
        "docs"
        "research"
        "specs"
        "tests"
        "node_modules"
    )

    # Find all directories with metadata.yaml (recursively)
    # This identifies image directories regardless of nesting depth
    while IFS= read -r metadata_file; do
        local image_dir
        image_dir=$(dirname "$metadata_file")

        # Get relative path from repo root
        local rel_path="${image_dir#${repo_root}/}"
        rel_path="${rel_path#./}"  # Remove leading ./ if present

        # Skip if path starts with excluded directory
        local skip=false
        for exclude in "${exclude_patterns[@]}"; do
            if [[ "$rel_path" == "$exclude"* ]]; then
                skip=true
                break
            fi
        done
        [[ "$skip" == "true" ]] && continue

        # Check if any Dockerfile exists alongside metadata.yaml
        # Accept either default Dockerfile or any Dockerfile.* variant
        if [[ -f "${image_dir}/Dockerfile" ]] || compgen -G "${image_dir}/Dockerfile.*" > /dev/null 2>&1; then
            images+=("$rel_path")
        fi
    done < <(find "$repo_root" -type f -name "metadata.yaml" 2>/dev/null)

    # Sort for consistent output
    printf '%s\n' "${images[@]}" | sort
}

# Get path to image directory
# Args:
#   $1: Repository root
#   $2: Image name
# Returns:
#   Full path to image directory
get_image_dir() {
    local repo_root="${1:-.}"
    local image_name="$2"
    echo "${repo_root}/${image_name}"
}

# Check if image exists
# Args:
#   $1: Repository root
#   $2: Image name
# Returns:
#   0 if image exists, 1 otherwise
image_exists() {
    local repo_root="${1:-.}"
    local image_name="$2"
    local image_dir
    image_dir=$(get_image_dir "$repo_root" "$image_name")

    if [[ -f "$image_dir/Dockerfile" ]] && [[ -f "$image_dir/metadata.yaml" ]]; then
        return 0
    fi
    return 1
}

# Get Dockerfile path for image
# Args:
#   $1: Repository root
#   $2: Image name
# Returns:
#   Path to Dockerfile
get_dockerfile() {
    local repo_root="${1:-.}"
    local image_name="$2"
    echo "$(get_image_dir "$repo_root" "$image_name")/Dockerfile"
}

# Get metadata.yaml path for image
# Args:
#   $1: Repository root
#   $2: Image name
# Returns:
#   Path to metadata.yaml
get_metadata() {
    local repo_root="${1:-.}"
    local image_name="$2"
    echo "$(get_image_dir "$repo_root" "$image_name")/metadata.yaml"
}

# Get history.jsonl path for image
# Args:
#   $1: Repository root
#   $2: Image name
# Returns:
#   Path to history.jsonl
get_history_file() {
    local repo_root="${1:-.}"
    local image_name="$2"
    echo "$(get_image_dir "$repo_root" "$image_name")/history.jsonl"
}

# Verify image directory has required files and structure
# Args:
#   $1: Image directory path (full path)
# Returns:
#   0 if valid, 1 if invalid
verify_image_directory() {
    local image_dir="${1:-.}"

    # Check metadata.yaml exists
    if [[ ! -f "$image_dir/metadata.yaml" ]]; then
        return 1
    fi

    # Check at least one Dockerfile exists (default or variant)
    if [[ ! -f "$image_dir/Dockerfile" ]] && ! compgen -G "$image_dir/Dockerfile.*" > /dev/null 2>&1; then
        return 1
    fi

    return 0
}

# Alias for compatibility with generate-matrix.sh naming
discover_image_directories() {
    discover_images "$@"
}
