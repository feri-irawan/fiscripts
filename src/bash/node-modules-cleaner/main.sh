#!/usr/bin/env bash
# ==============================================================================
# node-modules-cleaner.sh
#
# Version: 1.0.0
# Runtime: Bash
# Platform: Linux (tested)
#
# Description:
#   Safely find, inspect, filter, and interactively remove selected node_modules
#   directories below a user-provided scan root.
#
# Safety Architecture:
#   - Execution as root or via sudo is rejected.
#   - Filesystem root (/) and direct node_modules directories are rejected as scan root.
#   - Nested node_modules directories are pruned and ignored during scanning.
#   - Symlinks are never traversed; symlink targets are rejected.
#   - Re-validates targets immediately before permanent deletion.
#   - Requires interactive confirmation by typing 'DELETE' in all caps.
# ==============================================================================

set -u
set -o pipefail

readonly SCRIPT_NAME="${SCRIPT_NAME_OVERRIDE:-node-modules-cleaner.sh}"
readonly SCRIPT_VERSION="1.0.0"

# Source dependencies if executed directly from src/ during development
if ! declare -f human_size >/dev/null 2>&1; then
    _SRC_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../_lib" 2>/dev/null && pwd -P)"
    if [[ -n "$_SRC_LIB_DIR" && -d "$_SRC_LIB_DIR" ]]; then
        # shellcheck source=/dev/null
        [[ -f "$_SRC_LIB_DIR/colors.sh" ]] && source "$_SRC_LIB_DIR/colors.sh"
        # shellcheck source=/dev/null
        [[ -f "$_SRC_LIB_DIR/format.sh" ]] && source "$_SRC_LIB_DIR/format.sh"
    fi
fi

# Global State Arrays
NODE_MODULES=()
NODE_MODULES_SIZES=()
NODE_MODULES_KB=()
ORIG_INDEX=()
SELECTED=()

# Filter & Navigation State
FILTER_QUERY=""
VISIBLE_INDICES=()
CURRENT_CURSOR=0

# CLI Options & Paths
LIST_FILE=""
SCAN_ROOT=""
SCAN_ROOT_ABS=""
MODE="interactive"
SORT_MODE="default"

# ------------------------------------------------------------------------------
# Cleanup & Traps
# ------------------------------------------------------------------------------

# Remove temporary files on script exit
cleanup() {
    if [[ -n "$LIST_FILE" && -e "$LIST_FILE" ]]; then
        rm -f -- "$LIST_FILE"
    fi
}

on_interrupt() {
    cleanup
    printf '%s\n' "${RESET:-}"
    exit 130
}

trap cleanup EXIT
trap on_interrupt INT TERM

# ------------------------------------------------------------------------------
# Usage & Help Documentation
# ------------------------------------------------------------------------------

usage() {
    cat <<EOF
Usage:
  $SCRIPT_NAME [OPTIONS] SCAN_ROOT

Options:
  -h, --help            Show this help message and exit.
  -v, --version         Show the script version and exit.
  -l, --list, --dry-run List discovered node_modules without interactive deletion.
  -s, --sort <MODE>     Sort results by size, name, or default (default: default).

Arguments:
  SCAN_ROOT             Existing directory to scan recursively. It may contain one
                        or more projects, but must not itself be node_modules.

Description:
  Find node_modules directories below SCAN_ROOT, show a size summary,
  and open an interactive selector so you can choose which ones to remove.

  When a node_modules directory is found, its contents are pruned from the
  scan. This means nested node_modules directories are intentionally ignored.

Workflow:
  1. Scan SCAN_ROOT and show every eligible node_modules directory.
  2. Select one or more directories in the interactive selector.
  3. Review the selected paths and type DELETE to confirm permanent deletion.

Requirements:
  Bash, standard Unix utilities (find, rm, du, mktemp, awk, sort, basename,
  and dirname), and a TTY terminal for interactive mode. No Node.js or package
  manager is needed.

Examples:
  # Scan the current directory recursively.
  $SCRIPT_NAME .

  # Scan non-interactively and list disk space usage (dry-run).
  $SCRIPT_NAME --list "\$HOME/Projects"

  # Scan with initial sorting by largest size first.
  $SCRIPT_NAME --sort size "\$HOME/Projects"

  # Scan one project or a path containing spaces.
  $SCRIPT_NAME "\$HOME/Projects/my-app"
  $SCRIPT_NAME "\$HOME/Archived Projects"

Selector controls:
  Up/Down or j/k        Move between items.
  PgUp/PgDn             Move page by page.
  Space                 Toggle the current item.
  a                     Select all items currently visible.
  n                     Clear all selections currently visible.
  s                     Cycle sort mode (size -> name -> default).
  /                     Filter projects by keyword (Esc to clear).
  Enter                 Continue to the deletion review.
  q or Esc              Cancel and exit.

Safety behavior:
  - Running without arguments shows this help and makes no changes.
  - Only directories named exactly node_modules below SCAN_ROOT are eligible.
  - Symlinks are not followed during scanning and symlink targets are rejected.
  - Scanning stops at each node_modules directory; nested copies are ignored.
  - No deletion happens without interactive selection and an explicit DELETE.
  - The script refuses to run as root or through sudo.
  - SCAN_ROOT itself cannot be a node_modules directory.
  - The filesystem root (/) is rejected as SCAN_ROOT; choose a narrower path.
  - GNU rm --one-file-system is used when available to avoid crossing mount points.
  - Deletion is permanent; node_modules can be regenerated with your package
    manager (for example: npm install, pnpm install, yarn install, or bun install).

Version: $SCRIPT_VERSION
EOF
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

warn() {
    printf 'Warning: %s\n' "$*" >&2
}

# ------------------------------------------------------------------------------
# Argument Parsing
# ------------------------------------------------------------------------------

if (( $# == 0 )); then
    usage
    exit 0
fi

while (( $# > 0 )); do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--version)
            printf '%s %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"
            exit 0
            ;;
        -l|--list|--dry-run)
            MODE="list"
            shift
            ;;
        -s|--sort)
            if (( $# < 2 )); then
                die "option '$1' requires a mode: size, name, or default"
            fi
            SORT_MODE="$2"
            shift 2
            ;;
        --sort=*)
            SORT_MODE="${1#*=}"
            shift
            ;;
        --)
            shift
            break
            ;;
        -*)
            die "unknown option: $1"
            ;;
        *)
            if [[ -n "$SCAN_ROOT" ]]; then
                die "unexpected extra argument: $1"
            fi
            SCAN_ROOT="$1"
            shift
            ;;
    esac
done

if [[ -z "$SCAN_ROOT" ]]; then
    usage
    exit 0
fi

case "$SORT_MODE" in
    size|name|default) ;;
    *)
        die "invalid sort mode '$SORT_MODE' (must be: size, name, or default)"
        ;;
esac

# ------------------------------------------------------------------------------
# Pre-Flight Safety Checks
# ------------------------------------------------------------------------------

# Root / Sudo Guard
if (( EUID == 0 )) || [[ -n "${SUDO_USER:-}" || -n "${SUDO_UID:-}" ]]; then
    die "for safety, this script must not be run as root or through sudo"
fi

# Directory verification
[[ -d "$SCAN_ROOT" ]] || die "scan root is not an existing directory: $SCAN_ROOT"

# Resolve absolute path safely without changing working directory
SCAN_ROOT_ABS=$(cd -- "$SCAN_ROOT" 2>/dev/null && pwd -P) || {
    die "cannot access scan root: $SCAN_ROOT"
}

# Prevent scanning a node_modules directory itself
if [[ "${SCAN_ROOT_ABS##*/}" == 'node_modules' ]]; then
    die "scan root cannot itself be a node_modules directory; use its project directory parent"
fi

# Prevent scanning system filesystem root
if [[ "$SCAN_ROOT_ABS" == "/" ]]; then
    die "refusing to scan the filesystem root (/); choose a narrower project directory"
fi

# Ensure required core utilities are available
for required_command in find rm du mktemp awk sort basename dirname; do
    command -v "$required_command" >/dev/null 2>&1 || \
        die "command '$required_command' was not found"
done

# Check mount-point boundary support in rm
RM_OPTIONS=()
if command -v grep >/dev/null 2>&1 && rm --help 2>&1 | grep -q -- '--one-file-system'; then
    RM_OPTIONS+=(--one-file-system)
fi

# Interactive mode requires a valid TTY
if [[ "$MODE" == "interactive" ]]; then
    [[ -t 0 && -t 1 ]] || die "the interactive selector requires stdin and stdout to be a TTY"
fi

# ------------------------------------------------------------------------------
# Filesystem Scanning
# ------------------------------------------------------------------------------

LIST_FILE=$(mktemp "${TMPDIR:-/tmp}/node-modules-cleaner.XXXXXX") || {
    die "failed to create a temporary file for scan results"
}

printf 'Scanning recursively from: %s\n' "$SCAN_ROOT_ABS"
printf 'Rule: each node_modules directory is pruned from the scan;\n'
printf '      node_modules directories inside it will not be scanned.\n\n'

# -P prevents following symlinks.
# -prune avoids descending into nested node_modules.
# -print0 separates filenames with NUL characters for safe special character handling.
if ! find -P "$SCAN_ROOT_ABS" -type d -name node_modules -prune -print0 >"$LIST_FILE"; then
    die "scan failed or a directory could not be read; nothing was deleted"
fi

while IFS= read -r -d '' path; do
    NODE_MODULES+=("$path")
done <"$LIST_FILE"

if (( ${#NODE_MODULES[@]} == 0 )); then
    printf 'No node_modules directories found below %s.\n' "$SCAN_ROOT_ABS"
    exit 0
fi

printf 'Found %d eligible node_modules directories. Calculating sizes...\n\n' "${#NODE_MODULES[@]}"

for ((i = 0; i < ${#NODE_MODULES[@]}; i++)); do
    path="${NODE_MODULES[i]}"
    NODE_MODULES_SIZES+=("$(human_size "$path")")
    NODE_MODULES_KB+=("$(kb_size "$path")")
    ORIG_INDEX+=("$i")
    SELECTED+=(0)
done

# ------------------------------------------------------------------------------
# Sorting & Filtering Engine
# ------------------------------------------------------------------------------

apply_sort() {
    local target_mode=$1
    local count=${#NODE_MODULES[@]}
    if (( count <= 1 )); then
        return
    fi

    # Snapshot current arrays before reordering
    local prev_paths=("${NODE_MODULES[@]}")
    local prev_sizes=("${NODE_MODULES_SIZES[@]}")
    local prev_kb=("${NODE_MODULES_KB[@]}")
    local prev_orig=("${ORIG_INDEX[@]}")
    local prev_sel=("${SELECTED[@]}")

    local sort_input=""
    for ((i = 0; i < count; i++)); do
        local proj_dir
        proj_dir=$(dirname -- "${prev_paths[i]}")

        if [[ "$target_mode" == "size" ]]; then
            sort_input+="${prev_kb[i]}"$'\t'"${i}"$'\n'
        elif [[ "$target_mode" == "name" ]]; then
            sort_input+="${proj_dir}"$'\t'"${i}"$'\n'
        else
            sort_input+="${prev_orig[i]}"$'\t'"${i}"$'\n'
        fi
    done

    NODE_MODULES=()
    NODE_MODULES_SIZES=()
    NODE_MODULES_KB=()
    ORIG_INDEX=()
    SELECTED=()

    local sort_cmd
    if [[ "$target_mode" == "size" ]]; then
        sort_cmd="sort -t$'\t' -k1,1nr"
    elif [[ "$target_mode" == "name" ]]; then
        sort_cmd="sort -t$'\t' -k1,1"
    else
        sort_cmd="sort -t$'\t' -k1,1n"
    fi

    while IFS=$'\t' read -r _ item_idx; do
        [[ -z "$item_idx" ]] && continue
        NODE_MODULES+=("${prev_paths[item_idx]}")
        NODE_MODULES_SIZES+=("${prev_sizes[item_idx]}")
        NODE_MODULES_KB+=("${prev_kb[item_idx]}")
        ORIG_INDEX+=("${prev_orig[item_idx]}")
        SELECTED+=("${prev_sel[item_idx]}")
    done < <(printf '%s' "$sort_input" | eval "$sort_cmd")
}

update_visible_indices() {
    VISIBLE_INDICES=()
    local count=${#NODE_MODULES[@]}
    local prev_nocasematch
    prev_nocasematch=$(shopt -p nocasematch 2>/dev/null || true)
    shopt -s nocasematch 2>/dev/null || true

    for ((i = 0; i < count; i++)); do
        if [[ -z "$FILTER_QUERY" ]]; then
            VISIBLE_INDICES+=("$i")
        else
            local proj_dir
            proj_dir=$(dirname -- "${NODE_MODULES[i]}")
            if [[ "$proj_dir" == *"$FILTER_QUERY"* ]]; then
                VISIBLE_INDICES+=("$i")
            fi
        fi
    done

    if [[ "$prev_nocasematch" == *"shopt -u"* ]]; then
        shopt -u nocasematch 2>/dev/null || true
    fi
}

if [[ "$SORT_MODE" != "default" ]]; then
    apply_sort "$SORT_MODE"
fi

update_visible_indices

# ------------------------------------------------------------------------------
# Summary Table Display (CLI Table or Non-Interactive Exit)
# ------------------------------------------------------------------------------

printf '%-5s %-10s %s\n' 'No.' 'Size' 'Project directory'
printf '%-5s %-10s %s\n' '----' '----------' '------------------'
for ((i = 0; i < ${#NODE_MODULES[@]}; i++)); do
    printf '%-5d %-10s %s\n' "$((i + 1))" "${NODE_MODULES_SIZES[i]}" "$(dirname -- "${NODE_MODULES[i]}")"
done
printf '\nEstimated space that can be freed: %s\n' "$(total_size "${NODE_MODULES[@]}")"

# Non-interactive list / dry-run mode completes here
if [[ "$MODE" == "list" ]]; then
    exit 0
fi

# ------------------------------------------------------------------------------
# Interactive TUI Selector
# ------------------------------------------------------------------------------

selected_count() {
    local count=0
    local value
    for value in "${SELECTED[@]}"; do
        if (( value == 1 )); then
            ((count++))
        fi
    done
    printf '%d' "$count"
}

get_page_size() {
    local lines
    lines=$(tput lines 2>/dev/null || echo 24)
    if ! [[ "$lines" =~ ^[0-9]+$ ]] || (( lines < 12 )); then
        lines=24
    fi
    local page_size=$(( lines - 9 ))
    if (( page_size < 5 )); then
        page_size=5
    elif (( page_size > 20 )); then
        page_size=20
    fi
    printf '%d' "$page_size"
}

render_selector() {
    local cursor=$1
    local visible_count=${#VISIBLE_INDICES[@]}
    local total_count=${#NODE_MODULES[@]}
    local page_size
    page_size=$(get_page_size)

    local page=0
    local total_pages=1
    local start_idx=0
    local end_idx=0

    if (( visible_count > 0 )); then
        page=$(( cursor / page_size ))
        total_pages=$(( (visible_count + page_size - 1) / page_size ))
        start_idx=$(( page * page_size ))
        end_idx=$(( start_idx + page_size ))
        (( end_idx > visible_count )) && end_idx=$visible_count
    fi

    clear_screen
    printf '%sSelect node_modules directories to remove%s\n' "$BOLD" "$RESET"
    printf 'Scan root: %s | Sort: %s (s: cycle)\n' "$SCAN_ROOT_ABS" "$SORT_MODE"

    if [[ -n "$FILTER_QUERY" ]]; then
        printf 'Filter: "%s" (%d matching of %d total) [Press / to edit]\n' \
            "$FILTER_QUERY" "$visible_count" "$total_count"
    fi

    if (( visible_count == 0 )); then
        printf 'Page 0/0\n\n'
        printf '  %s(No directories match current filter "%s")%s\n' "$CLR_YELLOW" "$FILTER_QUERY" "$RESET"
    else
        printf 'Page %d/%d (showing items %d-%d of %d)\n\n' \
            "$((page + 1))" "$total_pages" "$((start_idx + 1))" "$end_idx" "$visible_count"

        for ((v = start_idx; v < end_idx; v++)); do
            local idx="${VISIBLE_INDICES[v]}"
            local mark=' '
            if (( SELECTED[idx] == 1 )); then
                mark='x'
            fi
            local line_prefix='  '
            if (( v == cursor )); then
                line_prefix='> '
                printf '%s' "$REVERSE"
            fi
            printf '%s[%s] %3d) %-10s %s%s\n' \
                "$line_prefix" "$mark" "$((idx + 1))" "${NODE_MODULES_SIZES[idx]}" \
                "$(dirname -- "${NODE_MODULES[idx]}")" "$RESET"
        done
    fi

    printf '\nSelected: %s/%s | ↑/↓ or j/k move | PgUp/PgDn page | Space toggle | a all | n none | / filter | s sort | Enter continue | q cancel\n' \
        "$(selected_count)" "$total_count"
}

on_winch() {
    render_selector "$CURRENT_CURSOR"
}

prompt_filter() {
    printf '\nEnter filter query (leave empty to clear filter): '
    local new_filter=""
    IFS= read -r new_filter || new_filter=""
    FILTER_QUERY="$new_filter"
    update_visible_indices
}

select_projects() {
    local cursor=0
    local key=''
    local key2=''
    local key3=''
    local _key4=''

    trap on_winch WINCH 2>/dev/null || true

    while :; do
        local visible_count=${#VISIBLE_INDICES[@]}
        if (( visible_count > 0 && cursor >= visible_count )); then
            cursor=$(( visible_count - 1 ))
        fi

        CURRENT_CURSOR=$cursor
        render_selector "$cursor"

        if ! IFS= read -r -s -n 1 key; then
            printf '\n'
            trap - WINCH 2>/dev/null || true
            return 2
        fi

        # Handle escape sequences (Arrows, Page Up/Down)
        if [[ "$key" == $'\033' ]]; then
            if IFS= read -r -s -n 1 -t 1 key2 && [[ "$key2" == '[' ]] && \
                IFS= read -r -s -n 1 -t 1 key3; then
                case "$key3" in
                    A|D) (( cursor > 0 )) && ((cursor--)) ;;
                    B|C) (( cursor < visible_count - 1 )) && ((cursor++)) ;;
                    5)
                        IFS= read -r -s -n 1 -t 1 _key4 || true
                        local ps
                        ps=$(get_page_size)
                        if (( cursor - ps >= 0 )); then
                            (( cursor -= ps ))
                        else
                            cursor=0
                        fi
                        ;;
                    6)
                        IFS= read -r -s -n 1 -t 1 _key4 || true
                        local ps
                        ps=$(get_page_size)
                        if (( cursor + ps < visible_count )); then
                            (( cursor += ps ))
                        else
                            (( visible_count > 0 )) && cursor=$(( visible_count - 1 ))
                        fi
                        ;;
                esac
            else
                # Standalone Esc pressed: if filter active, clear filter first; otherwise cancel.
                if [[ -n "$FILTER_QUERY" ]]; then
                    FILTER_QUERY=""
                    update_visible_indices
                    cursor=0
                else
                    trap - WINCH 2>/dev/null || true
                    return 2
                fi
            fi
            continue
        fi

        case "$key" in
            '')
                trap - WINCH 2>/dev/null || true
                return 0
                ;;
            ' ')
                if (( visible_count > 0 )); then
                    local target_idx="${VISIBLE_INDICES[cursor]}"
                    if (( SELECTED[target_idx] == 1 )); then
                        SELECTED[target_idx]=0
                    else
                        SELECTED[target_idx]=1
                    fi
                fi
                ;;
            a|A)
                for ((v = 0; v < visible_count; v++)); do
                    SELECTED[VISIBLE_INDICES[v]]=1
                done
                ;;
            n|N)
                for ((v = 0; v < visible_count; v++)); do
                    SELECTED[VISIBLE_INDICES[v]]=0
                done
                ;;
            s|S)
                local current_path=""
                if (( visible_count > 0 )); then
                    current_path="${NODE_MODULES[VISIBLE_INDICES[cursor]]}"
                fi
                case "$SORT_MODE" in
                    default) SORT_MODE="size" ;;
                    size)    SORT_MODE="name" ;;
                    name)    SORT_MODE="default" ;;
                esac
                apply_sort "$SORT_MODE"
                update_visible_indices
                if [[ -n "$current_path" ]]; then
                    for ((v = 0; v < ${#VISIBLE_INDICES[@]}; v++)); do
                        if [[ "${NODE_MODULES[VISIBLE_INDICES[v]]}" == "$current_path" ]]; then
                            cursor=$v
                            break
                        fi
                    done
                fi
                ;;
            '/')
                prompt_filter
                cursor=0
                ;;
            j|J)
                (( cursor < visible_count - 1 )) && ((cursor++))
                ;;
            k|K)
                (( cursor > 0 )) && ((cursor--))
                ;;
            q|Q)
                trap - WINCH 2>/dev/null || true
                return 2
                ;;
        esac
    done
}

if ! select_projects; then
    clear_screen
    printf 'Cancelled. Nothing was deleted.\n'
    exit 0
fi

clear_screen

# ------------------------------------------------------------------------------
# Deletion Confirmation Review
# ------------------------------------------------------------------------------

SELECTED_PATHS=()
SELECTED_SIZES=()
for ((i = 0; i < ${#NODE_MODULES[@]}; i++)); do
    if (( SELECTED[i] == 1 )); then
        SELECTED_PATHS+=("${NODE_MODULES[i]}")
        SELECTED_SIZES+=("${NODE_MODULES_SIZES[i]}")
    fi
done

if (( ${#SELECTED_PATHS[@]} == 0 )); then
    printf 'No items selected. Nothing was deleted.\n'
    exit 0
fi

printf '%sDeletion review%s\n\n' "$BOLD" "$RESET"
for ((i = 0; i < ${#SELECTED_PATHS[@]}; i++)); do
    printf '  [%s] %s\n' "${SELECTED_SIZES[i]}" "${SELECTED_PATHS[i]}"
done

printf '\nTotal: %d directories, approximately %s\n' \
    "${#SELECTED_PATHS[@]}" "$(total_size "${SELECTED_PATHS[@]}")"
printf '\nThe directories above will be permanently deleted.\n'
printf 'Type exactly %sDELETE%s and press Enter to continue: ' "$BOLD" "$RESET"

confirmation=''
IFS= read -r confirmation || confirmation=''
if [[ "$confirmation" != 'DELETE' ]]; then
    printf '\nCancelled. Nothing was deleted.\n'
    exit 0
fi

# ------------------------------------------------------------------------------
# Pre-Deletion Re-Validation (TOCTOU Defense)
# ------------------------------------------------------------------------------

printf '\nRe-validating targets before deletion...\n'

is_below_scan_root() {
    local candidate=$1

    if [[ "$SCAN_ROOT_ABS" == "/" ]]; then
        [[ "$candidate" == /* && "$candidate" != "/" ]]
    else
        [[ "$candidate" == "$SCAN_ROOT_ABS"/* ]]
    fi
}

for path in "${SELECTED_PATHS[@]}"; do
    is_below_scan_root "$path" || die "target is outside the scan root; aborting: $path"

    [[ "$(basename -- "$path")" == 'node_modules' ]] || \
        die "target name is invalid; aborting: $path"
    [[ -d "$path" && ! -L "$path" ]] || \
        die "target is not a regular directory or has changed; aborting: $path"
done

# ------------------------------------------------------------------------------
# Permanent Deletion Execution
# ------------------------------------------------------------------------------

removed=0
failed=0
total_to_remove=${#SELECTED_PATHS[@]}
for ((i = 0; i < total_to_remove; i++)); do
    path="${SELECTED_PATHS[i]}"
    printf '[%d/%d] Removing: %s\n' "$((i + 1))" "$total_to_remove" "$path"
    if rm -rf "${RM_OPTIONS[@]}" -- "$path"; then
        ((removed++))
    else
        printf 'Failed to remove: %s\n' "$path" >&2
        ((failed++))
    fi
done

printf '\nDone. Successfully removed: %d' "$removed"
if (( failed > 0 )); then
    printf ', failed: %d' "$failed"
fi
printf '.\n'

if (( failed > 0 )); then
    exit 1
fi
