#!/usr/bin/env bash
# ==============================================================================
# src/bash/_lib/colors.sh
#
# Terminal styling, ANSI color definitions, and display helpers.
# Automatically respects NO_COLOR and non-interactive/dumb terminals.
# ==============================================================================

# shellcheck disable=SC2034
init_colors() {
    if [[ -z "${TERM:-}" || "${TERM:-dumb}" == "dumb" || -n "${NO_COLOR:-}" ]]; then
        BOLD=''
        REVERSE=''
        RESET=''
        CLR_GREEN=''
        CLR_RED=''
        CLR_YELLOW=''
        CLR_BLUE=''
    else
        BOLD=$'\033[1m'
        REVERSE=$'\033[7m'
        RESET=$'\033[0m'
        CLR_GREEN=$'\033[0;32m'
        CLR_RED=$'\033[0;31m'
        CLR_YELLOW=$'\033[0;33m'
        CLR_BLUE=$'\033[0;34m'
    fi
}

clear_screen() {
    if command -v tput >/dev/null 2>&1 && [[ -n "${TERM:-}" && "${TERM:-dumb}" != "dumb" ]]; then
        tput clear 2>/dev/null || printf '\033[2J\033[H'
    else
        printf '\033[2J\033[H'
    fi
}

# Auto-initialize colors upon loading
init_colors
