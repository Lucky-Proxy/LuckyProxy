#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="${0##*/}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_RAW_ROOT="https://raw.githubusercontent.com/Lucky-Proxy/LuckyProxy"

CHANNEL="stable"
CUSTOM_URL=""
TARGET_DIR="$SCRIPT_DIR"
SKIP_ITEMS=0
FORCE=0
DEBUG=1
DOWNLOADER=""
ABI_MODE="auto"
INTERACTIVE=0
SELECTED_ABI=""
SELECTED_ABI_DIR=""
SELECTED_ABI_SHORT=""

TMP_FILES=()

C_RESET=""
C_BOLD=""
C_BLUE=""
C_GREEN=""
C_YELLOW=""
C_RED=""
C_BASE=""

usage() {
    cat <<'EOF'
Usage:
  bash installer.sh [stable|beta] [options]

Options:
  --interactive        Force interactive wizard mode.
  --url <CUSTOM_URL>   Override source URL/base.
  --abi <MODE>         ABI mode: auto | arm64 | armv7.
  --skip-items         Do not sync items.dat.
  --force              Replace files even if content is unchanged.
  --help, -h           Show this help.

Examples:
  bash installer.sh
  bash installer.sh --interactive
  bash installer.sh beta
  bash installer.sh stable --abi auto
  bash installer.sh --url https://raw.githubusercontent.com/Lucky-Proxy/LuckyProxy/main
  bash installer.sh --url https://raw.githubusercontent.com/Lucky-Proxy/LuckyProxy/main/LuckyProxy
  bash installer.sh --force
EOF
}

log_step() {
    printf '%b[%s/5]%b %s\n' "${C_BLUE}${C_BOLD}" "$1" "$C_RESET" "$2"
}

log_ok() {
    printf '%b[OK]%b %s\n' "$C_GREEN" "$C_RESET" "$1"
}

log_warn() {
    printf '%b[WARN]%b %s\n' "$C_YELLOW" "$C_RESET" "$1"
}

log_err() {
    printf '%b[ERR]%b %s\n' "$C_RED" "$C_RESET" "$1" >&2
}

log_debug() {
    if [[ "$DEBUG" -eq 1 ]]; then
        printf '%b[DEBUG]%b %s\n' "$C_BLUE" "$C_RESET" "$1"
    fi
}

log_info() {
    printf '%b[INFO]%b %s\n' "$C_BLUE" "$C_RESET" "$1"
}

die() {
    local message="$1"
    local hint="${2:-}"
    log_err "$message"
    if [[ -n "$hint" ]]; then
        printf '      %s\n' "$hint" >&2
    fi
    exit 1
}

cleanup() {
    local tmp
    for tmp in "${TMP_FILES[@]}"; do
        if [[ -n "$tmp" && -f "$tmp" ]]; then
            rm -f "$tmp"
        fi
    done
    return 0
}
trap cleanup EXIT

new_tmp_file() {
    local name="$1"
    local path="${INSTALL_DIR}/.${name}.tmp.$$.$RANDOM"
    TMP_FILES+=("$path")
    printf '%s\n' "$path"
}

require_value() {
    local flag="$1"
    local value="${2:-}"
    [[ -n "$value" ]] || die "Missing value for $flag." "Use '$SCRIPT_NAME --help' to see valid usage."
}

read_with_default() {
    local prompt="$1"
    local default_value="$2"
    local input=""
    printf '%s [%s]: ' "$prompt" "$default_value" >&2
    read -r input || true
    if [[ -z "$input" ]]; then
        printf '%s\n' "$default_value"
    else
        printf '%s\n' "$input"
    fi
}

ask_yes_no() {
    local prompt="$1"
    local default_value="$2"
    local input=""
    local normalized_default=""
    if [[ "$default_value" == "y" || "$default_value" == "Y" ]]; then
        normalized_default="y"
    else
        normalized_default="n"
    fi

    while true; do
        if [[ "$normalized_default" == "y" ]]; then
            printf '%s [Y/n]: ' "$prompt"
        else
            printf '%s [y/N]: ' "$prompt"
        fi

        read -r input || true
        if [[ -z "$input" ]]; then
            input="$normalized_default"
        fi

        case "$input" in
            y|Y|yes|YES)
                return 0
                ;;
            n|N|no|NO)
                return 1
                ;;
            *)
                log_warn "Invalid input. Please answer y or n."
                ;;
        esac
    done
}

run_interactive_wizard() {
    if [[ ! -t 0 ]]; then
        log_warn "Interactive mode skipped: no TTY detected. Using defaults/CLI args."
        return
    fi

    printf '\n%bLuckyProxy Installer Wizard%b\n' "${C_BLUE}${C_BOLD}" "$C_RESET"
    printf '%b%s%b\n' "$C_BLUE" '---------------------------' "$C_RESET"

    while true; do
        printf '\n%bSelect source channel:%b\n' "$C_BLUE" "$C_RESET"
        printf '  1) stable (recommended)\n'
        printf '  2) beta\n'
        printf '  3) custom URL\n'
        printf 'Choose [1-3]: '
        local source_choice=""
        read -r source_choice || true
        source_choice="${source_choice:-1}"
        case "$source_choice" in
            1)
                CHANNEL="stable"
                CUSTOM_URL=""
                break
                ;;
            2)
                CHANNEL="beta"
                CUSTOM_URL=""
                break
                ;;
            3)
                CHANNEL="stable"
                CUSTOM_URL="$(read_with_default "Enter custom URL (base or .../LuckyProxy)" "$CUSTOM_URL")"
                if [[ -z "$CUSTOM_URL" ]]; then
                    log_warn "Custom URL cannot be empty."
                else
                    break
                fi
                ;;
            *)
                log_warn "Invalid choice. Please select 1, 2, or 3."
                ;;
        esac
    done

    while true; do
        printf '\n%bSelect ABI mode:%b\n' "$C_BLUE" "$C_RESET"
        printf '  1) auto (recommended)\n'
        printf '  2) arm64\n'
        printf '  3) armv7\n'
        printf 'Choose [1-3]: '
        local abi_choice=""
        read -r abi_choice || true
        abi_choice="${abi_choice:-1}"
        case "$abi_choice" in
            1)
                ABI_MODE="auto"
                break
                ;;
            2)
                ABI_MODE="arm64"
                break
                ;;
            3)
                ABI_MODE="armv7"
                break
                ;;
            *)
                log_warn "Invalid choice. Please select 1, 2, or 3."
                ;;
        esac
    done

    if ask_yes_no "Sync items.dat?" "y"; then
        SKIP_ITEMS=0
    else
        SKIP_ITEMS=1
    fi

    if ask_yes_no "Force overwrite files even if unchanged?" "n"; then
        FORCE=1
    else
        FORCE=0
    fi

    printf '\n%bConfiguration Summary:%b\n' "${C_BLUE}${C_BOLD}" "$C_RESET"
    if [[ -n "$CUSTOM_URL" ]]; then
        printf '  Source    : custom (%s)\n' "$CUSTOM_URL"
    else
        printf '  Source    : %s\n' "$CHANNEL"
    fi
    printf '  ABI mode  : %s\n' "$ABI_MODE"
    if [[ "$SKIP_ITEMS" -eq 1 ]]; then
        printf '  items.dat : skip\n'
    else
        printf '  items.dat : sync\n'
    fi
    if [[ "$FORCE" -eq 1 ]]; then
        printf '  Force     : yes\n'
    else
        printf '  Force     : no\n'
    fi
    printf '  Directory : %s\n' "$TARGET_DIR"
    printf '  Debug     : on\n'

    if ! ask_yes_no "Proceed with installation?" "y"; then
        die "Installation cancelled by user." "Run the installer again when ready."
    fi
}

init_colors() {
    if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
        C_BASE=$'\033[0;32m'
        C_RESET="$C_BASE"
        C_BOLD=$'\033[1m'
        C_BLUE=$'\033[34m'
        C_GREEN=$'\033[1;32m'
        C_YELLOW=$'\033[33m'
        C_RED=$'\033[31m'
        printf '%b' "$C_BASE"
    fi
}

pick_downloader() {
    if command -v curl >/dev/null 2>&1; then
        DOWNLOADER="curl"
        return
    fi
    if command -v wget >/dev/null 2>&1; then
        DOWNLOADER="wget"
        return
    fi
    die "Neither curl nor wget was found." "Install one downloader first, then run again."
}

download_file() {
    local url="$1"
    local out="$2"

    rm -f "$out"
    if [[ "$DOWNLOADER" == "curl" ]]; then
        if [[ "$DEBUG" -eq 1 ]]; then
            log_debug "curl -fL --retry 2 --retry-delay 1 --connect-timeout 15 -o \"$out\" \"$url\""
            curl -fL --retry 2 --retry-delay 1 --connect-timeout 15 -o "$out" "$url" >/dev/null
        else
            curl -fsSL --retry 2 --retry-delay 1 --connect-timeout 15 -o "$out" "$url" >/dev/null 2>&1
        fi
        return $?
    fi

    if [[ "$DEBUG" -eq 1 ]]; then
        log_debug "wget -O \"$out\" \"$url\""
        wget -O "$out" "$url" >/dev/null
    else
        wget -q -O "$out" "$url" >/dev/null 2>&1
    fi
}

download_first() {
    local out="$1"
    shift
    local url
    for url in "$@"; do
        log_info "Downloading: $url"
        log_debug "Try download: $url"
        if download_file "$url" "$out"; then
            return 0
        fi
    done
    rm -f "$out"
    return 1
}

ensure_non_empty() {
    local file="$1"
    [[ -s "$file" ]] || return 1
    return 0
}

contains_launcher_pattern() {
    local file="$1"
    grep -q "arm64-v8a/LuckyProxy\|armeabi-v7a/LuckyProxy" "$file" 2>/dev/null
}

print_candidates() {
    local label="$1"
    shift
    log_err "Failed to download ${label}."
    printf '      Tried URLs:\n' >&2
    local u
    for u in "$@"; do
        printf '      - %s\n' "$u" >&2
    done
}

resolve_source() {
    SOURCE_KIND="$CHANNEL"
    BASE_URL=""
    BASE_URL_CANDIDATES=()
    PROXY_URL_CANDIDATES=()
    ABI_URL_CANDIDATES=()
    ITEMS_URL=""
    ITEMS_URL_CANDIDATES=()

    if [[ -n "$CUSTOM_URL" ]]; then
        SOURCE_KIND="custom"
        local custom="${CUSTOM_URL%/}"
        if [[ "$custom" == *"/LuckyProxy" ]]; then
            PROXY_URL_CANDIDATES=("$custom")
            BASE_URL="${custom%/LuckyProxy}"
            BASE_URL_CANDIDATES=("$BASE_URL")
        else
            BASE_URL="$custom"
            BASE_URL_CANDIDATES=("$BASE_URL")
            PROXY_URL_CANDIDATES=("$BASE_URL/LuckyProxy")
        fi

        local b
        for b in "${BASE_URL_CANDIDATES[@]}"; do
            [[ -n "$b" ]] || continue
            ABI_URL_CANDIDATES+=(
                "$b/${SELECTED_ABI_DIR}/LuckyProxy"
                "$b/out/android/${SELECTED_ABI_DIR}/LuckyProxy"
            )
            ITEMS_URL_CANDIDATES+=("$b/items.dat")
        done
        if [[ "${#ITEMS_URL_CANDIDATES[@]}" -gt 0 ]]; then
            ITEMS_URL="${ITEMS_URL_CANDIDATES[0]}"
        fi
        return
    fi

    if [[ "$CHANNEL" == "stable" ]]; then
        BASE_URL_CANDIDATES=("${REPO_RAW_ROOT}/main")
    else
        BASE_URL_CANDIDATES=("${REPO_RAW_ROOT}/beta")
    fi

    local base
    for base in "${BASE_URL_CANDIDATES[@]}"; do
        PROXY_URL_CANDIDATES+=("$base/LuckyProxy")
        ABI_URL_CANDIDATES+=(
            "$base/${SELECTED_ABI_DIR}/LuckyProxy"
            "$base/out/android/${SELECTED_ABI_DIR}/LuckyProxy"
        )
        ITEMS_URL_CANDIDATES+=("$base/items.dat")
    done
    BASE_URL="${BASE_URL_CANDIDATES[0]}"
    ITEMS_URL="${ITEMS_URL_CANDIDATES[0]}"
}

set_selected_abi() {
    local mode="$1"
    case "$mode" in
        arm64)
            SELECTED_ABI="arm64"
            SELECTED_ABI_SHORT="arm64"
            SELECTED_ABI_DIR="arm64-v8a"
            ;;
        armv7)
            SELECTED_ABI="armv7"
            SELECTED_ABI_SHORT="armv7"
            SELECTED_ABI_DIR="armeabi-v7a"
            ;;
        *)
            die "Unsupported ABI mode: $mode" "Use --abi auto|arm64|armv7."
            ;;
    esac
}

detect_abi_auto() {
    local abilist=""
    local machine=""

    if command -v getprop >/dev/null 2>&1; then
        abilist="$(getprop ro.product.cpu.abilist 2>/dev/null || true)"
        if [[ -z "$abilist" ]]; then
            abilist="$(getprop ro.product.cpu.abi 2>/dev/null || true)"
        fi
    fi

    machine="$(uname -m 2>/dev/null || true)"
    log_debug "Detected abilist: ${abilist:-<empty>}"
    log_debug "Detected uname -m: ${machine:-<empty>}"

    if echo "$abilist" | grep -qi "arm64-v8a\|aarch64"; then
        set_selected_abi "arm64"
        return
    fi
    if echo "$abilist" | grep -qi "armeabi-v7a\|armv7"; then
        set_selected_abi "armv7"
        return
    fi

    case "$machine" in
        aarch64|arm64)
            set_selected_abi "arm64"
            return
            ;;
        armv7l|armv8l|armv7|arm)
            set_selected_abi "armv7"
            return
            ;;
    esac

    log_warn "Auto-detect ABI failed (non-Android/unknown env). Falling back to arm64."
    set_selected_abi "arm64"
}

ORIGINAL_ARGC=$#
init_colors
while [[ $# -gt 0 ]]; do
    case "$1" in
        stable|beta)
            CHANNEL="$1"
            ;;
        latest)
            CHANNEL="stable"
            log_warn "Channel 'latest' is deprecated; using 'stable'."
            ;;
        --url)
            shift
            require_value "--url" "${1:-}"
            CUSTOM_URL="$1"
            ;;
        --interactive)
            INTERACTIVE=1
            ;;
        --abi)
            shift
            require_value "--abi" "${1:-}"
            ABI_MODE="$1"
            ;;
        --skip-items)
            SKIP_ITEMS=1
            ;;
        --force)
            FORCE=1
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            die "Unknown argument: $1" "Run '$SCRIPT_NAME --help' to see available options."
            ;;
    esac
    shift
done

if [[ "$INTERACTIVE" -eq 1 || "$ORIGINAL_ARGC" -eq 0 ]]; then
    run_interactive_wizard
fi

if [[ "$CHANNEL" != "stable" && "$CHANNEL" != "beta" ]]; then
    die "Invalid channel: $CHANNEL" "Use channel 'stable' or 'beta'."
fi

case "$ABI_MODE" in
    auto)
        detect_abi_auto
        ;;
    arm64|armv7)
        set_selected_abi "$ABI_MODE"
        ;;
    *)
        die "Invalid ABI mode: $ABI_MODE" "Use --abi auto|arm64|armv7."
        ;;
esac

if [[ -z "$SELECTED_ABI_DIR" ]]; then
    die "Internal error: ABI selection is empty." "Rerun installer with --abi arm64."
fi

log_step 1 "Preflight"
pick_downloader
mkdir -p "$TARGET_DIR"
INSTALL_DIR="$(cd "$TARGET_DIR" && pwd)"
[[ -d "$INSTALL_DIR" ]] || die "Install directory is not accessible: $TARGET_DIR"
touch "${INSTALL_DIR}/.installer-write-check.$$" 2>/dev/null || die "Cannot write to: $INSTALL_DIR" "Use --dir <writable_path>."
rm -f "${INSTALL_DIR}/.installer-write-check.$$"
log_ok "Downloader: $DOWNLOADER"
log_ok "Install dir: $INSTALL_DIR"
log_ok "Selected ABI: $SELECTED_ABI_SHORT ($SELECTED_ABI_DIR)"

log_step 2 "Resolve source (stable/beta/custom)"
resolve_source
log_ok "Source mode: $SOURCE_KIND"
if [[ "$SOURCE_KIND" == "custom" ]]; then
    log_ok "Custom URL: $CUSTOM_URL"
else
    log_ok "Channel: $CHANNEL"
fi
log_debug "Proxy candidate(s): ${PROXY_URL_CANDIDATES[*]}"
log_debug "ABI candidate(s): ${ABI_URL_CANDIDATES[*]}"
log_debug "Items URL candidate(s): ${ITEMS_URL_CANDIDATES[*]}"

log_step 3 "Download LuckyProxy (${SELECTED_ABI_SHORT})"
PROXY_PATH="${INSTALL_DIR}/LuckyProxy"
proxy_tmp="$(new_tmp_file "LuckyProxy")"
if ! download_first "$proxy_tmp" "${PROXY_URL_CANDIDATES[@]}"; then
    print_candidates "LuckyProxy" "${PROXY_URL_CANDIDATES[@]}"
    die "Install aborted." "Check source URL/channel or network, then retry."
fi

if ! ensure_non_empty "$proxy_tmp"; then
    die "Downloaded LuckyProxy is empty/corrupt." "Retry with '--force' or verify source URL."
fi

if contains_launcher_pattern "$proxy_tmp"; then
    log_warn "Launcher detected. Resolving ${SELECTED_ABI_SHORT} binary only."
    if [[ "${#ABI_URL_CANDIDATES[@]}" -eq 0 ]]; then
        die "No ABI candidate URL available for this source." "Use '--url <base_or_binary_url>' with valid ABI binary path."
    fi
    abi_tmp="$(new_tmp_file "LuckyProxy.abi")"
    if ! download_first "$abi_tmp" "${ABI_URL_CANDIDATES[@]}"; then
        print_candidates "${SELECTED_ABI_SHORT} LuckyProxy" "${ABI_URL_CANDIDATES[@]}"
        die "Install aborted." "Provide a valid source containing ${SELECTED_ABI_SHORT} LuckyProxy."
    fi
    if ! ensure_non_empty "$abi_tmp"; then
        die "Downloaded ${SELECTED_ABI_SHORT} LuckyProxy is empty/corrupt." "Verify source binary and retry."
    fi
    mv -f "$abi_tmp" "$proxy_tmp"
fi

if [[ "$FORCE" -eq 0 && -f "$PROXY_PATH" ]] && cmp -s "$proxy_tmp" "$PROXY_PATH"; then
    log_ok "LuckyProxy is already up to date."
    rm -f "$proxy_tmp"
else
    mv -f "$proxy_tmp" "$PROXY_PATH"
    chmod 755 "$PROXY_PATH"
    log_ok "LuckyProxy installed: $PROXY_PATH"
fi

log_step 4 "Sync items.dat"
ITEMS_PATH="${INSTALL_DIR}/items.dat"
if [[ "$SKIP_ITEMS" -eq 1 ]]; then
    log_warn "Skipping items.dat sync (--skip-items)."
else
    if [[ "${#ITEMS_URL_CANDIDATES[@]}" -eq 0 ]]; then
        log_warn "items.dat URL could not be derived from source; skipped."
    else
        items_tmp="$(new_tmp_file "items.dat")"
        if ! download_first "$items_tmp" "${ITEMS_URL_CANDIDATES[@]}"; then
            die "Failed to download items.dat." "Check source URL/network or rerun with --skip-items."
        fi
        if ! ensure_non_empty "$items_tmp"; then
            die "Downloaded items.dat is empty/corrupt." "Check source and retry."
        fi

        if [[ "$FORCE" -eq 0 && -f "$ITEMS_PATH" ]] && cmp -s "$items_tmp" "$ITEMS_PATH"; then
            log_ok "items.dat already up to date."
            rm -f "$items_tmp"
        else
            mv -f "$items_tmp" "$ITEMS_PATH"
            log_ok "items.dat updated: $ITEMS_PATH"
        fi
    fi
fi

log_step 5 "Finalize"
if [[ -t 1 ]]; then
    if command -v clear >/dev/null 2>&1; then
        clear
    fi
fi

printf '\n%bSUCCESS%b\n' "${C_GREEN}${C_BOLD}" "$C_RESET"
printf '  %bSource%b : %s\n' "$C_BLUE" "$C_RESET" "$SOURCE_KIND"
if [[ "$SOURCE_KIND" != "custom" ]]; then
    printf '  %bChannel%b: %s\n' "$C_BLUE" "$C_RESET" "$CHANNEL"
fi
printf '  %bABI%b    : %s (%s)\n' "$C_BLUE" "$C_RESET" "$SELECTED_ABI_SHORT" "$SELECTED_ABI_DIR"
printf '  %bDir%b    : %s\n' "$C_BLUE" "$C_RESET" "$INSTALL_DIR"
printf '  %bRun%b    : cd "%s" && ./LuckyProxy\n' "${C_GREEN}${C_BOLD}" "$C_RESET" "$INSTALL_DIR"
printf '  %bRun Proxy%b    : ./LuckyProxy\n'
