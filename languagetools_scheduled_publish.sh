#!/usr/bin/env bash
set -u

PROJECT_DIR="/opt/languagetools"
CONFIDENTIAL_DIR="/opt/languagetools-confidential"
REPORT_DIR="/opt/languagetools-may10"
BACKUP_DIR="/home/we6jbo/backup-this"
LOG_DIR="$PROJECT_DIR/logs"
LOGFILE="$LOG_DIR/languagetools_scheduled_publish.log"
HANDOFF_FILE="$REPORT_DIR/tk-handoff-514.txt"
SECRET_RAW="$REPORT_DIR/secret-scan-raw-514.txt"
SECRET_HITS="$REPORT_DIR/secret-scan-hits-514.txt"
STATUS_MARKER_FAIL="$REPORT_DIR/rjUZjXJ.txt"
STATUS_MARKER_SUCCESS="$REPORT_DIR/Vn57Ho6S.txt"

mkdir -p "$REPORT_DIR" "$BACKUP_DIR" "$LOG_DIR"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$*" | tee -a "$LOGFILE"
}

write_handoff() {
  local status="$1"
  local reason="$2"

  {
    echo "#AIS73 #VVtz #Tu #Ve"
    echo "LanguageTools 514 handoff"
    echo
    echo "STATUS: $status"
    echo "REASON: $reason"
    echo "CURRENT_DATE_TIME: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "PROJECT_DIR: $PROJECT_DIR"
    echo "CONFIDENTIAL_DIR: $CONFIDENTIAL_DIR"
    echo "LOGFILE: $LOGFILE"
    echo "HANDOFF_FILE: $HANDOFF_FILE"
    echo
    echo "GIT LOCATION CHECK:"
    echo "PWD_AT_GIT_TIME: $(pwd)"
    echo "GIT_TOPLEVEL: $(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null || echo UNKNOWN)"
    echo "TMP_USED_FLAG: NO"
    echo "TMP_EVIDENCE: none"
    echo
    echo "GIT STATUS:"
    git -C "$PROJECT_DIR" status --short --branch 2>&1 || true
    echo
    echo "RECENT LOG:"
    tail -100 "$LOGFILE" 2>/dev/null || true
    echo
    echo "SECRET SCAN HITS:"
    if [ -s "$SECRET_HITS" ]; then
      sed 's#/home/we6jbo#[HOM]#g; s#we6jbo#[USR]#g' "$SECRET_HITS"
    else
      echo "none"
    fi
    echo
    echo "QUESTION FOR CHATGPT:"
    echo "Please explain this LanguageTools publish result and write one safe repair script if needed."
  } > "$HANDOFF_FILE"

  if command -v python3 >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    python3 - "$HANDOFF_FILE" <<'PY' >/dev/null 2>&1 || true
import sys
from pathlib import Path
try:
    import tkinter as tk
except Exception:
    raise SystemExit(0)

p = Path(sys.argv[1])
text = p.read_text(errors="replace")

root = tk.Tk()
root.title("LanguageTools handoff - copy all")
root.geometry("1000x700")

label = tk.Label(root, text="Copy all text below and paste it into ChatGPT.")
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

[ -d "$PROJECT_DIR" ] || fail "Missing project directory"
[ -d "$PROJECT_DIR/.git" ] || fail "Missing .git directory"

cd "$PROJECT_DIR" || fail "Could not cd into project directory"

GIT_TOPLEVEL="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ "$GIT_TOPLEVEL" = "$PROJECT_DIR" ] || fail "Git top-level mismatch: $GIT_TOPLEVEL"

if [ -d "$PROJECT_DIR/.git/rebase-merge" ] || [ -d "$PROJECT_DIR/.git/rebase-apply" ]; then
  fail "Unfinished rebase detected. Run the rebase-clean repair script or resolve conflicts manually."
fi

log "PWD_AT_GIT_TIME: $(pwd)"
log "GIT_TOPLEVEL: $GIT_TOPLEVEL"
log "TMP_USED_FLAG: NO"
log "TMP_EVIDENCE: none"

ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
[ -n "$ORIGIN_URL" ] || fail "No origin remote configured"
log "Origin remote: $ORIGIN_URL"

BRANCH="$(git branch --show-current 2>/dev/null || true)"
[ -n "$BRANCH" ] || BRANCH="main"
log "Current branch: $BRANCH"

log "Fetching latest origin/$BRANCH before changing generated files."
git fetch origin "$BRANCH" --prune >> "$LOGFILE" 2>&1 || fail "git fetch failed"

log "Rebasing before making generated updates."
git rebase "origin/$BRANCH" >> "$LOGFILE" 2>&1 || fail "git rebase failed before generated update"

log "Updating generated code-version.txt after rebase."
{
  echo "LanguageTools code version"
  echo "Updated: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "Git branch: $BRANCH"
  echo "Git top-level: $GIT_TOPLEVEL"
} > "$PROJECT_DIR/code-version.txt"

[ -f "$PROJECT_DIR/code-about.txt" ] || fail "Missing code-about.txt"

log "Running improved secret/PII scan."
: > "$SECRET_RAW"
: > "$SECRET_HITS"

scan_file() {
  local f="$1"

  case "$f" in
    "$PROJECT_DIR/.git/"*) return 0 ;;
    "$PROJECT_DIR/logs/"*) return 0 ;;
    "$PROJECT_DIR/private/"*) return 0 ;;
    "$PROJECT_DIR/confidential/"*) return 0 ;;
    *.png|*.jpg|*.jpeg|*.gif|*.pdf|*.zip|*.gz|*.tar|*.tgz|*.xz|*.sqlite|*.db) return 0 ;;
  esac

  grep -nE -H \
    '(password[[:space:]]*=|passwd[[:space:]]*=|secret[[:space:]]*=|api[_-]?key[[:space:]]*=|token[[:space:]]*=|authorization:|bearer |PRIVATE KEY|BEGIN RSA PRIVATE KEY|BEGIN OPENSSH PRIVATE KEY|BEGIN EC PRIVATE KEY|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|ghp_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|-----BEGIN)' \
    "$f" >> "$SECRET_RAW" 2>/dev/null || true
}

while IFS= read -r f; do
  scan_file "$f"
done < <(find "$PROJECT_DIR" -type f 2>/dev/null)

while IFS= read -r line; do
  case "$line" in
    *"grep -nE -H"* ) continue ;;
    *"grep -nE"*"'(password"* ) continue ;;
    *"BEGIN RSA PRIVATE KEY"*"BEGIN OPENSSH PRIVATE KEY"*"BEGIN EC PRIVATE KEY"* ) continue ;;
    *"authorization:"*"bearer "*"PRIVATE KEY"* ) continue ;;
    *"AWS_ACCESS_KEY_ID"*"AWS_SECRET_ACCESS_KEY"*"github_pat_"* ) continue ;;
    *"scan_file()"* ) continue ;;
    *"SECRET_RAW"* ) continue ;;
    *"SECRET_HITS"* ) continue ;;
  esac
  printf '%s\n' "$line" >> "$SECRET_HITS"
done < "$SECRET_RAW"

if [ -s "$SECRET_HITS" ]; then
  log "Possible real sensitive material found. Push blocked."
  sed 's#/home/we6jbo#[HOM]#g; s#we6jbo#[USR]#g' "$SECRET_HITS" | tee -a "$LOGFILE"
  fail "Secret/PII scan blocked publish. Review $SECRET_HITS"
fi

log "No real sensitive content found by improved scanner."

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
