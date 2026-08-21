#!/usr/bin/env bash
# ==============================================================================
# src/bash/_lib/format.sh
#
# Filesystem formatting and size calculation utilities.
# Portable across Linux (GNU coreutils) and macOS/BSD systems.
# ==============================================================================

# Calculate human-readable disk size of a given path.
human_size() {
    local target_path=$1
    local formatted_size

    formatted_size=$(du -sh -- "$target_path" 2>/dev/null | awk '{print $1}')
    if [[ -n "$formatted_size" ]]; then
        printf '%s' "$formatted_size"
    else
        printf '%s' 'unknown'
    fi
}

# Calculate exact integer size in Kilobytes for sorting and arithmetic.
kb_size() {
    local target_path=$1
    local numeric_kb

    numeric_kb=$(du -sk -- "$target_path" 2>/dev/null | awk '{print $1}')
    if [[ "$numeric_kb" =~ ^[0-9]+$ ]]; then
        printf '%s' "$numeric_kb"
    else
        printf '0'
    fi
}

# Sum and format total disk size from a list of paths portably without GNU du -c.
total_size() {
    if (( $# == 0 )); then
        printf '0 B'
        return
    fi

    local total_kb=0
    local current_kb
    while read -r current_kb _; do
        if [[ "$current_kb" =~ ^[0-9]+$ ]]; then
            (( total_kb += current_kb ))
        fi
    done < <(du -sk -- "$@" 2>/dev/null)

    if (( total_kb >= 1048576 )); then
        awk -v kb="$total_kb" 'BEGIN { printf "%.1f GB", kb / 1048576 }'
    elif (( total_kb >= 1024 )); then
        awk -v kb="$total_kb" 'BEGIN { printf "%.1f MB", kb / 1024 }'
    else
        printf '%d KB' "$total_kb"
    fi
}
