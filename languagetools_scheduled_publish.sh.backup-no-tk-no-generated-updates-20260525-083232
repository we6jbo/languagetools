#!/usr/bin/env bash
# LanguageTools scheduled publish
# Clean Operation May20 version
# This script intentionally avoids scanner self-matches and avoids publishing backup folders.

set -u

PROJECT_DIR="/opt/languagetools"
CONFIDENTIAL_DIR="/opt/languagetools-confidential"
LOGFILE="$CONFIDENTIAL_DIR/logging-info.txt"
HANDOFF_FILE="/home/we6jbo/languagetools-share-to-chatgpt.txt"
OPERATION_MAY20_LOCK="$CONFIDENTIAL_DIR/operationmay20.lock"
STATUS_MARKER_SUCCESS="$CONFIDENTIAL_DIR/last-publish-success.txt"
STATUS_MARKER_FAIL="$CONFIDENTIAL_DIR/last-publish-fail.txt"
SECRET_RAW="$CONFIDENTIAL_DIR/secret-scan-raw.txt"
SECRET_HITS="$CONFIDENTIAL_DIR/secret-scan-hits.txt"

KNOWN_PRE_MAY20_MD5_A="7e785669398d3e0c5fa97c592e618365"
KNOWN_PRE_MAY20_MD5_B="3024c2c2d643dc81a032a4df9badac5e"

log() {
    mkdir -p "$CONFIDENTIAL_DIR"
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$*" | tee -a "$LOGFILE"
}

file_md5() {
    if [ -f "$1" ]; then
        md5sum "$1" | awk '{print $1}'
    else
        printf 'MISSING'
    fi
}

# Required user-named function.
# It checks MD5 values on files this workflow may interact with.
check-pre-may-20() {
    local f md5

    {
        echo "#AIS73 #VVtz #Tu #Ve"
        echo "OPERATION MAY20"
        echo
        echo "Created: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "PROJECT_DIR: $PROJECT_DIR"
        echo "CONFIDENTIAL_DIR: $CONFIDENTIAL_DIR"
        echo "LOCK_FILE: $OPERATION_MAY20_LOCK"
        echo
        echo "Instruction to ChatGPT:"
        echo "Run operation may20 using any matched file location and md5sum below."
        echo "For any new .py Tk scripts, incorporate this same check into Tk dialog boxes."
        echo "Each Tk dialog box should display the matched file location and md5sum."
        echo
    } > "$HANDOFF_FILE"

    for f in \
        "$PROJECT_DIR/languagetools_scheduled_publish.sh" \
        "$PROJECT_DIR/code-about.txt" \
        "$PROJECT_DIR/code-version.txt" \
        "$PROJECT_DIR/.gitignore"
    do
        if [ -e "$f" ]; then
            md5="$(file_md5 "$f")"
            log "check-pre-may-20 md5: $md5  $f"

            if [ "$md5" = "$KNOWN_PRE_MAY20_MD5_A" ] || [ "$md5" = "$KNOWN_PRE_MAY20_MD5_B" ]; then
                {
                    echo "MATCHED_PRE_MAY20_FILE:"
                    echo "Location: $f"
                    echo "Name: $(basename "$f")"
                    echo "MD5: $md5"
                    echo "Instruction to ChatGPT: run operation may20 using file '$f' with md5sum '$md5'."
                    echo
                } >> "$HANDOFF_FILE"
            fi
        fi
    done
}

operation_may20_one_time_cleanup() {
    if [ -f "$OPERATION_MAY20_LOCK" ]; then
        log "Operation May20 lock exists. Not clearing future backup folders."
        return 0
    fi

    log "Operation May20 lock missing. Clearing old backup folders one time."

    local moved_dir="$CONFIDENTIAL_DIR/operationmay20-moved-backups-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$moved_dir"
    chmod 700 "$moved_dir" 2>/dev/null || true

    find "$PROJECT_DIR" -maxdepth 1 -type d \
        \( -name 'backup-before-self-scan-fix-*' -o -name 'backup-before-*' \) \
        -prune -exec mv -t "$moved_dir" {} + 2>/dev/null || true

    if [ -d "/tmp/languagetools-publish/repo" ]; then
        find "/tmp/languagetools-publish/repo" -type d \
            \( -name 'backup-before-self-scan-fix-*' -o -name 'backup-before-*' \) \
            -prune -exec rm -rf {} + 2>/dev/null || true
    fi

    {
        echo "operationmay20 completed one-time cleanup"
        echo "Created: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "Moved project backups to: $moved_dir"
    } > "$OPERATION_MAY20_LOCK"
    chmod 600 "$OPERATION_MAY20_LOCK" 2>/dev/null || true
    log "Created Operation May20 lock: $OPERATION_MAY20_LOCK"
}

build_sensitive_scan_regex() {
    # Split scanner words so the scanner does not flag the regex builder itself.
    local sp='[[:space:]]*'
    local eq='='
    local p1="pass""word"
    local p2="pass""wd"
    local p3="sec""ret"
    local p4="api[_-]?""key"
    local p5="tok""en"
    local p6="authori""zation:"
    local p7="bear""er "
    local p8="PRIVATE"" KEY"
    local p9="BEGIN RSA ""PRIVATE"" KEY"
    local p10="BEGIN OPENSSH ""PRIVATE"" KEY"
    local p11="BEGIN EC ""PRIVATE"" KEY"
    local p12="AWS_ACCESS""_KEY_ID"
    local p13="AWS_SECRET""_ACCESS_KEY"
    local p14="ghp_""[A-Za-z0-9_]{20,}"
    local p15="github_pat_""[A-Za-z0-9_]{20,}"
    local p16="-----""BEGIN"

    printf '%s\n' "(${p1}${sp}${eq}|${p2}${sp}${eq}|${p3}${sp}${eq}|${p4}${sp}${eq}|${p5}${sp}${eq}|${p6}|${p7}|${p8}|${p9}|${p10}|${p11}|${p12}|${p13}|${p14}|${p15}|${p16})"
}

is_scanner_implementation_line() {
    local file="$1"
    local line="$2"

    case "$file" in
        */languagetools_scheduled_publish.sh)
            case "$line" in
                *build_sensitive_scan_regex* ) return 0 ;;
                *scan_for_sensitive_content* ) return 0 ;;
                *sensitive_re* ) return 0 ;;
                *'local p'*'='* ) return 0 ;;
                *'KNOWN_PRE_MAY20_MD5_'* ) return 0 ;;
                *'Instruction to ChatGPT:'*'operation may20'* ) return 0 ;;
            esac
            ;;
    esac

    return 1
}

scan_for_sensitive_content() {
    local scan_root="${1:-$PROJECT_DIR}"
    local tmp_hits f line sensitive_re
    tmp_hits="$(mktemp)"
    sensitive_re="$(build_sensitive_scan_regex)"

    : > "$tmp_hits"

    find "$scan_root" \
        -path "$scan_root/.git" -prune -o \
        -path "$scan_root/logs" -prune -o \
        -path "$scan_root/private" -prune -o \
        -path "$scan_root/confidential" -prune -o \
        -type d \( -name 'backup-before-self-scan-fix-*' -o -name 'backup-before-*' \) -prune -o \
        -type f \( \
            -iname '*.sh' -o -iname '*.py' -o -iname '*.txt' -o -iname '*.md' -o \
            -iname '*.json' -o -iname '*.yaml' -o -iname '*.yml' -o -iname '*.ini' -o \
            -iname '*.conf' -o -iname '*.cfg' -o -iname '*.service' -o -iname '*.desktop' \
        \) -print 2>/dev/null | while IFS= read -r f; do
            awk -v re="$sensitive_re" '
                $0 ~ re {
                    print FILENAME ":" FNR ":" $0
                }
            ' "$f" 2>/dev/null
        done | while IFS= read -r line; do
            f="${line%%:*}"
            content="${line#*:}"
            content="${content#*:}"

            if is_scanner_implementation_line "$f" "$content"; then
                continue
            fi

            printf '%s\n' "$line"
        done > "$tmp_hits"

    cp "$tmp_hits" "$SECRET_RAW" 2>/dev/null || true

    if [ -s "$tmp_hits" ]; then
        cp "$tmp_hits" "$SECRET_HITS" 2>/dev/null || true
        cat "$tmp_hits"
        rm -f "$tmp_hits"
        return 1
    fi

    : > "$SECRET_HITS"
    rm -f "$tmp_hits"
    return 0
}

write_handoff() {
    local status="$1"
    local reason="$2"
    local md5_script

    md5_script="$(file_md5 "$PROJECT_DIR/languagetools_scheduled_publish.sh")"

    {
        echo "#AIS73 #VVtz #Tu #Ve"
        echo "LanguageTools Operation May20 handoff"
        echo
        echo "STATUS: $status"
        echo "REASON: $reason"
        echo "CURRENT_DATE_TIME: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "PROJECT_DIR: $PROJECT_DIR"
        echo "CONFIDENTIAL_DIR: $CONFIDENTIAL_DIR"
        echo "LOCK_FILE: $OPERATION_MAY20_LOCK"
        echo "SCHEDULED_SCRIPT: $PROJECT_DIR/languagetools_scheduled_publish.sh"
        echo "SCHEDULED_SCRIPT_MD5: $md5_script"
        echo
        echo "OPERATION MAY20 INSTRUCTION TO CHATGPT:"
        echo "Run operation may20 using the scheduled script location and md5sum above."
        echo "If creating or editing future .py Tk scripts, include check-pre-may-20 logic in the Tk dialog text."
        echo "The Tk dialog should show file location, name, and md5sum."
        echo "If the lock file exists, do not clear future backup folders automatically."
        echo "If the lock file does not exist, clear old backup-before-* folders once, then create the lock."
        echo
        echo "GIT STATUS:"
        git -C "$PROJECT_DIR" status --short --branch 2>&1 || true
        echo
        echo "RECENT LOG:"
        tail -120 "$LOGFILE" 2>/dev/null || true
        echo
        echo "SECRET SCAN HITS:"
        if [ -s "$SECRET_HITS" ]; then
            sed 's#/home/we6jbo#[HOM]#g; s#we6jbo#[USR]#g' "$SECRET_HITS"
        else
            echo "none"
        fi
    } > "$HANDOFF_FILE"

    if command -v python3 >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
        python3 - "$HANDOFF_FILE" "$PROJECT_DIR/languagetools_scheduled_publish.sh" "$md5_script" <<'PY' >/dev/null 2>&1 || true
import sys
from pathlib import Path
try:
    import tkinter as tk
except Exception:
    raise SystemExit(0)

handoff = Path(sys.argv[1])
script_path = sys.argv[2]
md5_value = sys.argv[3]
text = handoff.read_text(errors="replace")

root = tk.Tk()
root.title("LanguageTools Operation May20 handoff - copy all")
root.geometry("1050x760")

header = (
    "Copy all text below and paste it into ChatGPT.\n"
    f"Operation May20 file: {script_path}\n"
    f"MD5: {md5_value}\n"
    "Tell ChatGPT: run operation may20 using this file and md5sum."
)
label = tk.Label(root, text=header, justify="left")
label.pack(anchor="w", padx=10, pady=5)

box = tk.Text(root, wrap="word")
box.pack(fill="both", expand=True, padx=10, pady=10)
box.insert("1.0", text)

def copy_all():
    root.clipboard_clear()
    root.clipboard_append(box.get("1.0", "end-1c"))

btn = tk.Button(root, text="Copy all", command=copy_all)
btn.pack(pady=5)

root.mainloop()
PY
    fi
}

fail() {
    log "FAIL: $*"
    printf 'FAILED %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" > "$STATUS_MARKER_FAIL"
    write_handoff "failure" "$*"
    exit 1
}

log "============================================================"
log "LanguageTools scheduled publish started"
log "CURRENT_DATE_TIME: $(date '+%Y-%m-%d %H:%M:%S %Z')"
log "PROJECT_DIR: $PROJECT_DIR"
log "PWD_BEFORE_CD: $(pwd)"
log "============================================================"

check-pre-may-20
operation_may20_one_time_cleanup

[ -d "$PROJECT_DIR" ] || fail "Missing project directory"
[ -d "$PROJECT_DIR/.git" ] || fail "Missing .git directory"

cd "$PROJECT_DIR" || fail "Could not cd into project directory"

GIT_TOPLEVEL="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ "$GIT_TOPLEVEL" = "$PROJECT_DIR" ] || fail "Git top-level mismatch: $GIT_TOPLEVEL"

if [ -d "$PROJECT_DIR/.git/rebase-merge" ] || [ -d "$PROJECT_DIR/.git/rebase-apply" ]; then
    fail "Unfinished rebase detected. Resolve or abort the rebase before publishing."
fi

ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
[ -n "$ORIGIN_URL" ] || fail "No origin remote configured"
log "Origin remote: $ORIGIN_URL"

BRANCH="$(git branch --show-current 2>/dev/null || true)"
[ -n "$BRANCH" ] || BRANCH="main"
log "Current branch: $BRANCH"

log "Fetching latest origin/$BRANCH."
git fetch origin "$BRANCH" --prune >> "$LOGFILE" 2>&1 || fail "git fetch failed"

log "Rebasing before generated update."
git rebase "origin/$BRANCH" >> "$LOGFILE" 2>&1 || fail "git rebase failed before generated update"

log "Updating generated code-version.txt after rebase."
{
    echo "LanguageTools code version"
    echo "Updated: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "Git branch: $BRANCH"
    echo "Git top-level: $GIT_TOPLEVEL"
    echo "Operation May20 lock: $OPERATION_MAY20_LOCK"
} > "$PROJECT_DIR/code-version.txt"

[ -f "$PROJECT_DIR/code-about.txt" ] || fail "Missing code-about.txt"

log "Running improved secret/PII scan."
if scan_for_sensitive_content "$PROJECT_DIR"; then
    log "No real sensitive content found by improved scanner."
else
    log "Possible real sensitive material found. Push blocked."
    sed 's#/home/we6jbo#[HOM]#g; s#we6jbo#[USR]#g' "$SECRET_HITS" | tee -a "$LOGFILE"
    fail "Secret/PII scan blocked publish. Review $SECRET_HITS"
fi

log "Checking local LanguageTool server health."
if command -v curl >/dev/null 2>&1; then
    LT_RESPONSE="$(curl -sS --max-time 3 -X POST \
        -d 'language=en-US' \
        --data-urlencode 'text=This are a test.' \
        http://127.0.0.1:8081/v2/check 2>/dev/null || true)"

    if printf '%s' "$LT_RESPONSE" | grep -q '"matches"'; then
        log "LanguageTool server responded correctly."
    else
        log "WARNING: LanguageTool server did not respond correctly. This does not block GitHub publishing."
    fi
fi

log "Staging public repo changes."
git add -A >> "$LOGFILE" 2>&1 || fail "git add failed"

if git diff --cached --quiet; then
    log "No staged changes to commit."
else
    git commit -m "Stabilize LanguageTools publish workflow $(date '+%Y-%m-%d %H:%M:%S %Z')" >> "$LOGFILE" 2>&1 || fail "git commit failed"
fi

log "Pushing to GitHub."
git push -u origin "$BRANCH" >> "$LOGFILE" 2>&1 || fail "git push failed"

printf 'SUCCESS %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" > "$STATUS_MARKER_SUCCESS"

log "SUCCESS: GitHub push completed."
write_handoff "success" "GitHub push completed successfully."
exit 0
