
# Jeremiah / ChatGPT repair note:
# Avoid false positives where the secret scanner flags its own regex strings.
# Real secrets should still be blocked.
SECRET_SCAN_ALLOWLIST="/opt/languagetools-confidential/secret-scan-allowlist.regex"

filter_secret_scan_hits() {
    local infile="$1"
    if [ ! -s "$infile" ]; then
        return 0
    fi

    if [ -f "$SECRET_SCAN_ALLOWLIST" ]; then
        grep -v -f "$SECRET_SCAN_ALLOWLIST" "$infile" || true
    else
        cat "$infile"
    fi
}

#!/usr/bin/env bash
set -u

# #AIS73 #VVtz
# LanguageTools audit / ChatGPT handoff script
# Goal: near-zero-cost, long-lived, privacy-aware checks with Tk popup handoff.

PROJECT_DIR="/opt/languagetools"
CONFIDENTIAL_DIR="/opt/languagetools-confidential"
TMP_FIX_DIR="/tmp/a"
TMP_FIX_SCRIPT="${TMP_FIX_DIR}/run.sh"
OUTFILE="/home/we6jbo/send-to-chatgpt-languagetools.txt"
LOGDIR="${PROJECT_DIR}/logs"
STATEFILE="/tmp/languagetools-last-run.txt"
RUNLOG="${LOGDIR}/audit.log"
PORT="8081"
LT_URL="http://127.0.0.1:${PORT}/v2/check"
TEST_TEXT="This are a role of paper."
REPO_URL="https://github.com/we6jbo/languagetools"
RAW_CODE_VERSION_URL="https://raw.githubusercontent.com/we6jbo/languagetools/master/code-version.txt"
CODE_ABOUT_FILE="${PROJECT_DIR}/code-about.txt"
MAX_AGE_DAYS=21
THROTTLE_SECONDS=21600
HOSTNAME_NOW="$(hostname 2>/dev/null || echo unknown)"
USER_NOW="$(id -un 2>/dev/null || echo unknown)"
UID_NOW="$(id -u 2>/dev/null || echo unknown)"
PWD_NOW="$(pwd 2>/dev/null || echo unknown)"
NOW_HUMAN="$(date '+%Y-%m-%d %H:%M:%S %Z')"
NOW_EPOCH="$(date +%s)"
TODAY="$(date '+%Y-%m-%d')"

mkdir -p "$LOGDIR" "$TMP_FIX_DIR"
: > "$OUTFILE"
: > "$RUNLOG"

PROBLEMS=()
WARNINGS=()
INFOS=()
SENSITIVE_HITS=()
NONPRIVATE_MISSING=()

append_out() {
    printf '%s\n' "$*" >> "$OUTFILE"
    printf '%s\n' "$*" >> "$RUNLOG"
}

add_problem() {
    PROBLEMS+=("$*")
    append_out "PROBLEM: $*"
}

add_warning() {
    WARNINGS+=("$*")
    append_out "WARNING: $*"
}

add_info() {
    INFOS+=("$*")
    append_out "INFO: $*"
}

recently_ran() {
    [ -f "$STATEFILE" ] || return 1
    local last diff
    last="$(cat "$STATEFILE" 2>/dev/null || true)"
    [ -n "$last" ] || return 1
    diff=$((NOW_EPOCH - last))
    [ "$diff" -lt "$THROTTLE_SECONDS" ]
}

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

check_basics() {
    append_out "========================================"
    append_out "LANGUAGETOOLS AUDIT REPORT"
    append_out "TIME: $NOW_HUMAN"
    append_out "DATE: $TODAY"
    append_out "HOST: $HOSTNAME_NOW"
    append_out "USER: $USER_NOW"
    append_out "UID: $UID_NOW"
    append_out "PWD: $PWD_NOW"
    append_out "PROJECT_DIR: $PROJECT_DIR"
    append_out "CONFIDENTIAL_DIR: $CONFIDENTIAL_DIR"
    append_out "TMP_FIX_SCRIPT: $TMP_FIX_SCRIPT"
    append_out "REPO_URL: $REPO_URL"
    append_out "========================================"

    [ -d "$PROJECT_DIR" ] || add_problem "Project directory missing: $PROJECT_DIR"
    [ -d "$CONFIDENTIAL_DIR" ] || add_warning "Confidential directory missing: $CONFIDENTIAL_DIR"

    have_cmd git || add_problem "git is not installed or not in PATH"
    have_cmd curl || add_problem "curl is not installed or not in PATH"
    have_cmd python3 || add_problem "python3 is not installed or not in PATH"

    if have_cmd python3; then
        if ! python3 - <<'PY' >/dev/null 2>&1
import tkinter
from tkinter import scrolledtext
PY
        then
            add_problem "python3 is present but Tkinter is unavailable"
        else
            add_info "Tkinter is available"
        fi
    fi
}

check_code_about() {
    if [ -f "$CODE_ABOUT_FILE" ]; then
        add_info "Found code-about file: $CODE_ABOUT_FILE"
        append_out "----- BEGIN code-about.txt -----"
        sed 's/^/CODE_ABOUT: /' "$CODE_ABOUT_FILE" >> "$OUTFILE"
        append_out "----- END code-about.txt -----"
    else
        add_warning "Missing code-about file: $CODE_ABOUT_FILE"
    fi
}

check_languagetool_server() {
    if ! have_cmd curl; then
        add_problem "Cannot check LanguageTool server because curl is missing"
        return
    fi

    local response
    response="$(curl -m 10 -sS -X POST "$LT_URL" -d "language=en-US" --data-urlencode "text=$TEST_TEXT" 2>/dev/null || true)"
    if printf '%s' "$response" | grep -q '"matches"'; then
        add_info "LanguageTool server is responding at $LT_URL"
    else
        add_warning "LanguageTool server did not respond correctly at $LT_URL"
    fi
}

fetch_remote_code_version() {
    REMOTE_CODE_VERSION_RAW=""
    REMOTE_LAST_UPDATED=""
    REMOTE_AGE_DAYS="unknown"
    REMOTE_FETCH_STATUS="unknown"

    if ! have_cmd curl; then
        add_problem "Cannot fetch GitHub code-version.txt because curl is missing"
        return
    fi

    REMOTE_CODE_VERSION_RAW="$(curl -L -m 20 -fsS "$RAW_CODE_VERSION_URL" 2>/dev/null || true)"

    if [ -z "$REMOTE_CODE_VERSION_RAW" ]; then
        REMOTE_FETCH_STATUS="missing_or_private"
        add_problem "Could not fetch $RAW_CODE_VERSION_URL. Repo may be missing, private, or code-version.txt may not exist."
        return
    fi

    REMOTE_FETCH_STATUS="ok"
    append_out "REMOTE_CODE_VERSION_RAW: ${REMOTE_CODE_VERSION_RAW}"

    REMOTE_LAST_UPDATED="$(printf '%s\n' "$REMOTE_CODE_VERSION_RAW" | grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}([ T][0-9]{2}:[0-9]{2}(:[0-9]{2})?)?' | head -n 1 || true)"

    if [ -z "$REMOTE_LAST_UPDATED" ]; then
        add_warning "Fetched code-version.txt but could not parse a date from it"
        return
    fi

    local remote_epoch
    remote_epoch="$(date -d "$REMOTE_LAST_UPDATED" +%s 2>/dev/null || true)"
    if [ -z "$remote_epoch" ]; then
        add_warning "Could not convert remote code-version date into epoch: $REMOTE_LAST_UPDATED"
        return
    fi

    REMOTE_AGE_DAYS=$(( (NOW_EPOCH - remote_epoch) / 86400 ))
    add_info "Remote code-version date: $REMOTE_LAST_UPDATED (${REMOTE_AGE_DAYS} days old)"

    if [ "$REMOTE_AGE_DAYS" -gt "$MAX_AGE_DAYS" ]; then
        add_warning "GitHub code-version.txt appears stale: ${REMOTE_AGE_DAYS} days old"
    fi
}

check_local_git_repo() {
    LOCAL_GIT_OK="no"
    LOCAL_TRACKED_COUNT="0"
    LOCAL_HAS_REMOTE="no"
    ORIGIN_URL=""

    if [ ! -d "$PROJECT_DIR" ]; then
        add_problem "Cannot inspect git state because project directory does not exist"
        return
    fi

    if [ ! -d "$PROJECT_DIR/.git" ]; then
        add_problem "$PROJECT_DIR is not a git repository yet"
        return
    fi

    LOCAL_GIT_OK="yes"
    LOCAL_TRACKED_COUNT="$(git -C "$PROJECT_DIR" ls-files 2>/dev/null | wc -l | tr -d ' ')"
    add_info "Local git repository detected with ${LOCAL_TRACKED_COUNT} tracked files"

    ORIGIN_URL="$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null || true)"
    if [ -n "$ORIGIN_URL" ]; then
        LOCAL_HAS_REMOTE="yes"
        add_info "Local git origin: $ORIGIN_URL"
        case "$ORIGIN_URL" in
            *github.com/we6jbo/languagetools*|*github.com:we6jbo/languagetools*)
                add_info "Origin appears to point at the intended repo"
                ;;
            *)
                add_warning "Origin does not appear to point at $REPO_URL"
                ;;
        esac
    else
        add_problem "Local git repo exists, but no origin remote is configured"
    fi
}

scan_for_sensitive_content() {
    [ -d "$PROJECT_DIR" ] || return

    local hitfile tmp_hits
    tmp_hits="$(mktemp)"

    find "$PROJECT_DIR" \
        -path "$PROJECT_DIR/.git" -prune -o \
        -type f \( \
            -iname '*.sh' -o -iname '*.py' -o -iname '*.txt' -o -iname '*.md' -o \
            -iname '*.json' -o -iname '*.yaml' -o -iname '*.yml' -o -iname '*.ini' -o \
            -iname '*.conf' -o -iname '*.cfg' -o -iname '*.service' -o -iname '*.desktop' \
        \) -print 2>/dev/null | while read -r hitfile; do
            grep -nE -H '(password\s*=|passwd\s*=|secret\s*=|api[_-]?key|token\s*=|authorization:|bearer |PRIVATE KEY|BEGIN RSA PRIVATE KEY|BEGIN OPENSSH PRIVATE KEY|client_secret|aws_access_key_id|aws_secret_access_key|-----BEGIN)' "$hitfile" 2>/dev/null
        done > "$tmp_hits" || true

    if [ -s "$tmp_hits" ]; then
        while IFS= read -r line; do
            SENSITIVE_HITS+=("$line")
        done < "$tmp_hits"
        add_problem "Possible sensitive material found in project files. Review before any GitHub upload."
        append_out "----- POSSIBLE SENSITIVE HITS -----"
        sed 's/^/SENSITIVE: /' "$tmp_hits" >> "$OUTFILE"
        append_out "----- END POSSIBLE SENSITIVE HITS -----"
    else
        add_info "No obvious secret patterns found in scanned project files"
    fi

    rm -f "$tmp_hits"

    if find "$PROJECT_DIR" -type f \( -iname '*.pem' -o -iname '*.key' -o -iname 'id_rsa' -o -iname '.env' \) 2>/dev/null | grep -q .; then
        add_problem "High-risk secret-style filenames were found in the project tree"
        find "$PROJECT_DIR" -type f \( -iname '*.pem' -o -iname '*.key' -o -iname 'id_rsa' -o -iname '.env' \) 2>/dev/null | sed 's/^/HIGH_RISK_FILE: /' >> "$OUTFILE"
    fi
}

check_private_file_placement() {
    [ -d "$PROJECT_DIR" ] || return

    local private_name_hits
    private_name_hits="$(find "$PROJECT_DIR" -type f \( -iname '*private*' -o -iname '*secret*' -o -iname '*credential*' -o -iname '*token*' -o -iname '*confidential*' \) 2>/dev/null || true)"
    if [ -n "$private_name_hits" ]; then
        add_warning "Files with private-looking names still exist under $PROJECT_DIR and may belong in $CONFIDENTIAL_DIR"
        printf '%s\n' "$private_name_hits" | sed 's/^/PRIVATE_NAME_HIT: /' >> "$OUTFILE"
    else
        add_info "No obviously private-looking filenames found in $PROJECT_DIR"
    fi
}

compare_local_to_git_tracking() {
    [ -d "$PROJECT_DIR" ] || return
    [ -d "$PROJECT_DIR/.git" ] || return

    local tmp_all tmp_tracked tmp_missing
    tmp_all="$(mktemp)"
    tmp_tracked="$(mktemp)"
    tmp_missing="$(mktemp)"

    find "$PROJECT_DIR" -path "$PROJECT_DIR/.git" -prune -o -type f -print \
        | sed "s#^$PROJECT_DIR/##" \
        | grep -v '^logs/' \
        | grep -v '^\.gitignore$' \
        | sort -u > "$tmp_all"

    git -C "$PROJECT_DIR" ls-files 2>/dev/null | sort -u > "$tmp_tracked"

    comm -23 "$tmp_all" "$tmp_tracked" > "$tmp_missing" || true

    if [ -s "$tmp_missing" ]; then
        while IFS= read -r line; do
            NONPRIVATE_MISSING+=("$line")
        done < "$tmp_missing"
        add_warning "There are files in $PROJECT_DIR not currently tracked by git"
        append_out "----- UNTRACKED FILES IN PROJECT_DIR -----"
        sed 's/^/UNTRACKED: /' "$tmp_missing" >> "$OUTFILE"
        append_out "----- END UNTRACKED FILES -----"
    else
        add_info "All visible non-log files under $PROJECT_DIR appear tracked by git"
    fi

    rm -f "$tmp_all" "$tmp_tracked" "$tmp_missing"
}

cost_and_longevity_analysis() {
    append_out "----- COST AND LONGEVITY ANALYSIS -----"

    if have_cmd bash && have_cmd python3 && have_cmd git && have_cmd curl; then
        add_info "Core stack uses common low-cost tools: bash, python3, git, curl"
    fi

    if [ -d "$PROJECT_DIR" ]; then
        local size_kb
        size_kb="$(du -sk "$PROJECT_DIR" 2>/dev/null | awk '{print $1}')"
        append_out "COST_NOTE: Local project size is approximately ${size_kb:-unknown} KB"
    fi

    append_out "LONGEVITY_NOTE: Prefer plain text, shell, python3, git, and raw text manifests over paid services or proprietary dependencies."
    append_out "LONGEVITY_NOTE: Keep confidential data outside the public repo in $CONFIDENTIAL_DIR."
    append_out "LONGEVITY_NOTE: Keep a code-version.txt and code-about.txt in source control for human-readable maintenance."
    append_out "LONGEVITY_NOTE: Prefer scripts that degrade gracefully when GitHub is private, missing, or offline."
    append_out "LONGEVITY_NOTE: Avoid automatic push until the PII/secret scan passes and the tracked-file review is clean."
    append_out "----- END COST AND LONGEVITY ANALYSIS -----"
}

write_fixme_script() {
    cat > "$TMP_FIX_SCRIPT" <<'EOF_FIX'
#!/usr/bin/env bash
set -u

echo "Placeholder fix script created by audit."
echo "ChatGPT should replace this file with the exact repair logic for the problems listed in the Tk popup."
EOF_FIX
    chmod 700 "$TMP_FIX_SCRIPT"
    add_info "Prepared placeholder fix script path: $TMP_FIX_SCRIPT"
}

build_chatgpt_message() {
    CHATGPT_MESSAGE_FILE="$(mktemp)"
    {
        echo "#AIS73 #VVtz"
        echo "ChatGPT, how can I make this better?"
        echo
        echo "Please analyze my LanguageTools project and help me fix everything below."
        echo "I prefer that you write a repair script to: $TMP_FIX_SCRIPT"
        echo "Please avoid giving me many separate shell commands when a single repair script is possible."
        echo
        echo "CURRENT DATE/TIME: $NOW_HUMAN"
        echo "HOST: $HOSTNAME_NOW"
        echo "USER: $USER_NOW"
        echo "UID: $UID_NOW"
        echo "CURRENT WORKING DIRECTORY: $PWD_NOW"
        echo "PROJECT DIRECTORY: $PROJECT_DIR"
        echo "CONFIDENTIAL DIRECTORY: $CONFIDENTIAL_DIR"
        echo "REPO URL: $REPO_URL"
        echo "RAW CODE VERSION URL: $RAW_CODE_VERSION_URL"
        echo
        echo "PROJECT GOALS:"
        echo "1. Near-zero-cost stack."
        echo "2. Long-term durability and maintainability."
        echo "3. Private data must stay out of the public repo."
        echo "4. Public repo should mirror current non-private files from $PROJECT_DIR."
        echo "5. Secret and PII checks must happen before upload."
        echo "6. Tk popup should let me copy everything in one step and paste into ChatGPT."
        echo
        echo "GITHUB STATUS:"
        echo "REMOTE_FETCH_STATUS: ${REMOTE_FETCH_STATUS:-unknown}"
        echo "REMOTE_LAST_UPDATED: ${REMOTE_LAST_UPDATED:-unknown}"
        echo "REMOTE_AGE_DAYS: ${REMOTE_AGE_DAYS:-unknown}"
        echo "LOCAL_GIT_OK: ${LOCAL_GIT_OK:-unknown}"
        echo "LOCAL_HAS_REMOTE: ${LOCAL_HAS_REMOTE:-unknown}"
        echo "LOCAL_ORIGIN_URL: ${ORIGIN_URL:-unknown}"
        echo "LOCAL_TRACKED_COUNT: ${LOCAL_TRACKED_COUNT:-unknown}"
        echo
        echo "PROBLEMS FOUND:"
        if [ "${#PROBLEMS[@]}" -eq 0 ]; then
            echo "- none"
        else
            for item in "${PROBLEMS[@]}"; do
                echo "- $item"
            done
        fi
        echo
        echo "WARNINGS FOUND:"
        if [ "${#WARNINGS[@]}" -eq 0 ]; then
            echo "- none"
        else
            for item in "${WARNINGS[@]}"; do
                echo "- $item"
            done
        fi
        echo
        echo "UNTRACKED OR MISSING-FROM-GIT ITEMS UNDER PROJECT_DIR:"
        if [ "${#NONPRIVATE_MISSING[@]}" -eq 0 ]; then
            echo "- none detected"
        else
            for item in "${NONPRIVATE_MISSING[@]}"; do
                echo "- $item"
            done
        fi
        echo
        echo "POSSIBLE SENSITIVE HITS:"
        if [ "${#SENSITIVE_HITS[@]}" -eq 0 ]; then
            echo "- none detected by pattern scan"
        else
            for item in "${SENSITIVE_HITS[@]}"; do
                echo "- $item"
            done
        fi
        echo
        echo "CODE-ABOUT CONTENT:"
        if [ -f "$CODE_ABOUT_FILE" ]; then
            cat "$CODE_ABOUT_FILE"
        else
            echo "code-about.txt missing"
        fi
        echo
        echo "WHAT I WANT FROM CHATGPT:"
        echo "- Write or rewrite $TMP_FIX_SCRIPT so it resolves all identified problems."
        echo "- Keep private files out of the public repo."
        echo "- Improve the PII/secret safety check before GitHub upload."
        echo "- Improve repo verification so it confirms current non-private files are in GitHub."
        echo "- Improve cost and longevity planning while keeping the stack near zero cost."
        echo "- Keep the Tk popup copy/paste workflow simple."
    } > "$CHATGPT_MESSAGE_FILE"
}

show_tk_popup() {
    [ -f "$CHATGPT_MESSAGE_FILE" ] || return 1
    have_cmd python3 || return 1

    python3 - "$CHATGPT_MESSAGE_FILE" <<'PY'
import sys
import tkinter as tk
from tkinter import scrolledtext

path = sys.argv[1]
with open(path, 'r', encoding='utf-8', errors='replace') as f:
    text = f.read()

root = tk.Tk()
root.title("Paste this into ChatGPT")
root.geometry("1100x760")

label = tk.Label(root, text="Paste this into ChatGPT. The text is already selected and copied.", anchor="w", justify="left")
label.pack(fill="x", padx=8, pady=(8, 4))

box = scrolledtext.ScrolledText(root, wrap="word", undo=False)
box.pack(fill="both", expand=True, padx=8, pady=8)
box.insert("1.0", text)
box.focus_set()
box.tag_add("sel", "1.0", "end-1c")

try:
    root.clipboard_clear()
    root.clipboard_append(text)
    root.update()
except Exception:
    pass

root.mainloop()
PY
}

main() {
    check_basics

    if recently_ran; then
        add_info "Throttle active. This script ran recently, but continuing because an audit was requested."
    fi

    check_code_about
    check_languagetool_server
    fetch_remote_code_version
    check_local_git_repo
    scan_for_sensitive_content
    check_private_file_placement
    compare_local_to_git_tracking
    cost_and_longevity_analysis
    write_fixme_script
    build_chatgpt_message

    if [ "${#PROBLEMS[@]}" -gt 0 ] || [ "${#WARNINGS[@]}" -gt 0 ]; then
        add_info "Problems or warnings found. Launching Tk ChatGPT handoff window."
        show_tk_popup || add_problem "Failed to launch Tk popup window"
    else
        add_info "No major problems found. Launching Tk summary window anyway because this workflow is meant for ChatGPT review."
        show_tk_popup || add_problem "Failed to launch Tk popup window"
    fi

    printf '%s\n' "$NOW_EPOCH" > "$STATEFILE"
    add_info "Audit complete"
}

main "$@"


# CHATGPT_SECRET_SCAN_FALSE_POSITIVE_REPAIR
# If scheduled publish still fails, paste the new log to ChatGPT.
# The recurring hits from May 5-7, 2026 appear to be scanner-pattern false positives:
# run.sh and languagetools_scheduled_publish.sh contain the regex text used to detect secrets.
