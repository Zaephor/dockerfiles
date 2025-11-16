#!/usr/bin/env bash
# validate-doc-references.sh - Validate internal documentation references
#
# Usage:
#   validate-doc-references.sh
#
# Description:
#   Validates that all internal markdown links in documentation files
#   point to existing files or directories. Checks README.md, CONTRIBUTING.md,
#   and all markdown files in the docs/ directory.
#
# Exit Codes:
#   0 - All references valid
#   1 - One or more references point to missing files

set -euo pipefail

# Script metadata
# shellcheck disable=SC2034
SCRIPT_NAME="$(basename "$0")"

# Disable immediate exit for validation loop
set +e
EXIT_CODE=0

echo "Checking internal documentation references..."

# Function to validate links in a file
validate_links() {
    local file="$1"
    local display_name="$2"
    local file_dir
    file_dir="$(dirname "$file")"
    local has_error=0

    # Extract markdown links: [text](path)
    while IFS= read -r link; do
        # Skip URLs (http://, https://)
        if [[ "$link" =~ ^http ]]; then
            continue
        fi

        # Skip pure anchors (start with #)
        if [[ "$link" =~ ^#.* ]]; then
            continue
        fi

        # Strip anchor/fragment from link (e.g., file.md#section → file.md)
        local link_without_fragment="${link%%#*}"

        # Resolve relative path from the file's directory
        local resolved_path
        if [[ "$link_without_fragment" == /* ]]; then
            # Absolute path from repo root
            resolved_path="${link_without_fragment#/}"
        elif [[ "$link_without_fragment" == ../* ]] || [[ "$link_without_fragment" == ./* ]]; then
            # Relative path - resolve from file's directory using readlink
            # readlink -f requires the file to exist, so we use -m for missing files
            resolved_path="$(cd "$file_dir" && readlink -m "$link_without_fragment")"
            # Make path relative to repo root
            resolved_path="${resolved_path#$(pwd)/}"
        else
            # No prefix - try from file's directory first, then repo root
            if [ -f "${file_dir}/${link_without_fragment}" ] || [ -d "${file_dir}/${link_without_fragment}" ]; then
                resolved_path="${file_dir}/${link_without_fragment}"
            else
                resolved_path="$link_without_fragment"
            fi
        fi

        # Check if file exists (after resolving path)
        if [ ! -f "$resolved_path" ] && [ ! -d "$resolved_path" ]; then
            echo "  ✗ Missing reference in $display_name: $link (resolved to: $resolved_path)"
            has_error=1
        else
            echo "  ✓ Valid reference: $link"
        fi
    done < <(grep -o '\[.*\]([^)]*)' "$file" | sed 's/.*(\(.*\))/\1/')

    return $has_error
}

# Check README.md for references
if [ -f "README.md" ]; then
    echo "Checking README.md references..."
    if ! validate_links "README.md" "README.md"; then
        EXIT_CODE=1
    fi
fi

# Check CONTRIBUTING.md for references
if [ -f "CONTRIBUTING.md" ]; then
    echo "Checking CONTRIBUTING.md references..."
    if ! validate_links "CONTRIBUTING.md" "CONTRIBUTING.md"; then
        EXIT_CODE=1
    fi
fi

# Check docs/ directory references
if [ -d "docs" ]; then
    echo "Checking docs/ directory references..."

    for doc_file in docs/*.md; do
        if [ -f "$doc_file" ]; then
            if ! validate_links "$doc_file" "$(basename "$doc_file")"; then
                EXIT_CODE=1
            fi
        fi
    done
fi

if [ $EXIT_CODE -eq 0 ]; then
    echo "All internal references valid"
fi

exit $EXIT_CODE
