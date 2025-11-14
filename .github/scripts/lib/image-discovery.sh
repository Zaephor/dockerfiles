#!/usr/bin/env bash
# Image discovery library
# Discovers all Docker image directories at repository root level
# Images are identified by presence of both Dockerfile and metadata.yaml

set -euo pipefail

# Discover all image directories in repository
# Discovers directories at project root containing Dockerfile and metadata.yaml
# Args:
#   $1: Repository root directory
# Returns:
#   Array of image directory names (not full paths)
discover_images() {
    local repo_root="${1:-.}"
    local -a images=()

    # Find directories at root level (excluding hidden dirs and special dirs)
    local -a exclude_dirs=(".github" "docs" "research" "specs" "tests")

    while IFS= read -r -d '' dir; do
        local dir_name
        dir_name=$(basename "$dir")

        # Skip excluded directories
        local skip=false
        for exclude in "${exclude_dirs[@]}"; do
            if [[ "$dir_name" == "$exclude" ]]; then
                skip=true
                break
            fi
        done
        [[ "$skip" == "true" ]] && continue

        # Skip hidden directories
        [[ "$dir_name" =~ ^\.+ ]] && continue

        # Check if both Dockerfile and metadata.yaml exist
        if [[ -f "$dir/Dockerfile" ]] && [[ -f "$dir/metadata.yaml" ]]; then
            images+=("$dir_name")
        fi
    done < <(find "$repo_root" -maxdepth 1 -type d -print0)

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

    if [[ ! -f "$image_dir/Dockerfile" ]]; then
        return 1
    fi

    if [[ ! -f "$image_dir/metadata.yaml" ]]; then
        return 1
    fi

    return 0
}

# Alias for compatibility with generate-matrix.sh naming
discover_image_directories() {
    discover_images "$@"
}
