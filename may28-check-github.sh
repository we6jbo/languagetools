#!/usr/bin/env bash

# MASTERGUI_LANGUAGETOOLS_GUARD_PATCH_START
if [ -f '/home/we6jbo/.mastergui_languagetools_guard/shell_guard.sh' ]; then
  . '/home/we6jbo/.mastergui_languagetools_guard/shell_guard.sh'
fi
# MASTERGUI_LANGUAGETOOLS_GUARD_PATCH_END

set -u

BASE_DIR="/opt/languagetools"
TEST_FILE="$BASE_DIR/tested-again2.txt"
LOG_FILE="$BASE_DIR/may28-check-github.log"

GITHUB_URL="https://github.com"
RAW_GITHUB_URL="https://raw.githubusercontent.com"

mkdir -p "$BASE_DIR"

log_msg() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

gui_alert() {
    local title="$1"
    local message="$2"

    if command -v zenity >/dev/null 2>&1; then
        zenity --error --title="$title" --text="$message" 2>/dev/null || true
    elif command -v notify-send >/dev/null 2>&1; then
        notify-send "$title" "$message" 2>/dev/null || true
    else
        log_msg "$title: $message"
    fi
}

log_msg "may28-check-github.sh started."

if [[ ! -f "$TEST_FILE" ]]; then
    log_msg "tested-again2.txt does not exist. Creating it now."
    touch "$TEST_FILE"
else
    log_msg "tested-again2.txt already exists."
fi

GITHUB_OK=0
RAW_GITHUB_OK=0

if curl --output /dev/null --silent --head --fail --max-time 15 "$GITHUB_URL"; then
    GITHUB_OK=1
    log_msg "GitHub reachable: $GITHUB_URL"
else
    log_msg "GitHub NOT reachable: $GITHUB_URL"
fi

if curl --output /dev/null --silent --head --fail --max-time 15 "$RAW_GITHUB_URL"; then
    RAW_GITHUB_OK=1
    log_msg "Raw GitHub reachable: $RAW_GITHUB_URL"
else
    log_msg "Raw GitHub NOT reachable: $RAW_GITHUB_URL"
fi

if [[ "$GITHUB_OK" -eq 0 || "$RAW_GITHUB_OK" -eq 0 ]]; then
    gui_alert "Deployment Error" "languagetools may not be reaching GitHub correctly. Check $LOG_FILE"
    log_msg "Deployment Error alert shown."
    exit 1
fi

log_msg "GitHub check passed."
exit 0
