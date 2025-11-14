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

    # Extract markdown links: [text](path)
    grep -o '\[.*\]([^)]*)' "$file" | sed 's/.*(\(.*\))/\1/' | while read -r link; do
        # Skip URLs (http://, https://)
        if [[ "$link" =~ ^http ]]; then
            continue
        fi

        # Skip fragments and anchors
        if [[ "$link" =~ ^#.* ]]; then
            continue
        fi

        # Check if file exists
        if [ ! -f "$link" ] && [ ! -d "$link" ]; then
            echo "  ✗ Missing reference in $display_name: $link"
            return 1
        else
            echo "  ✓ Valid reference: $link"
        fi
    done
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
