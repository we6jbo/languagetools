#!/usr/bin/env bash
set -u

# Direct LanguageTools Git publish repair
# This version commits and pushes directly from /opt/languagetools.
# It does NOT use /tmp/languagetools-publish/repo.

PROJECT_DIR="/opt/languagetools"
CONFIDENTIAL_DIR="/opt/languagetools-confidential"
BACKUP_DIR="/home/we6jbo/backup-this"
REPO_URL="https://github.com/we6jbo/languagetools.git"

MARKER_FILE="/opt/languagetools/Vn57Ho6S.txt"
SUCCESS_TEXT="Vn57Ho6S"
FAIL_TEXT="rjUZjXJ"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$CONFIDENTIAL_DIR/reports"
REPORT="$REPORT_DIR/direct-publish-repair-$STAMP.txt"

mkdir -p "$BACKUP_DIR" "$REPORT_DIR" 2>/dev/null

write_marker_success() {
    {
        echo "$SUCCESS_TEXT"
        echo "STATUS=SUCCESS"
        echo "TIME=$(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "PROJECT_DIR=$PROJECT_DIR"
    } > "$MARKER_FILE"
}

write_marker_fail() {
    {
        echo "$FAIL_TEXT"
        echo "STATUS=FAILED"
        echo "TIME=$(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "PROJECT_DIR=$PROJECT_DIR"
        echo "REPORT=$REPORT"
    } > "$MARKER_FILE"
}

log() {
    echo "$*" | tee -a "$REPORT"
}

fail() {
    log "PROBLEM: $*"
    write_marker_fail
    log "Failure marker written to: $MARKER_FILE"
    log "Report saved to: $REPORT"
    exit 1
}

log "========================================"
log "LANGUAGETOOLS DIRECT PUBLISH REPAIR"
log "TIME: $(date '+%Y-%m-%d %H:%M:%S %Z')"
log "HOST: $(hostname)"
log "USER: $(id -un)"
log "PWD: $(pwd)"
log "PROJECT_DIR: $PROJECT_DIR"
log "REPO_URL: $REPO_URL"
log "MARKER_FILE: $MARKER_FILE"
log "REPORT: $REPORT"
log "========================================"

[ -d "$PROJECT_DIR" ] || fail "PROJECT_DIR does not exist: $PROJECT_DIR"

cd "$PROJECT_DIR" || fail "Could not cd to $PROJECT_DIR"

log ""
log "=== BACKUP /opt/languagetools ==="

tar -czf "$BACKUP_DIR/languagetools-direct-before-publish-$STAMP.tar.gz" \
    -C "$(dirname "$PROJECT_DIR")" "$(basename "$PROJECT_DIR")" \
    >>"$REPORT" 2>&1 \
    || fail "Backup failed"

log "INFO: Backup saved to $BACKUP_DIR/languagetools-direct-before-publish-$STAMP.tar.gz"

log ""
log "=== PREVENT LOCAL STATUS FILES FROM BEING COMMITTED ==="

if [ -d ".git" ]; then
    mkdir -p .git/info
    touch .git/info/exclude

    grep -qxF "Vn57Ho6S.txt" .git/info/exclude || echo "Vn57Ho6S.txt" >> .git/info/exclude
    grep -qxF "direct_publish_repair.sh" .git/info/exclude || echo "direct_publish_repair.sh" >> .git/info/exclude
fi

log "INFO: Local marker/script exclusion prepared if .git exists."

log ""
log "=== CHECK OR INITIALIZE GIT REPO ==="

if [ ! -d ".git" ]; then
    log "WARNING: /opt/languagetools is not currently a git repo."
    log "INFO: Initializing git repo directly in /opt/languagetools."
    git init >>"$REPORT" 2>&1 || fail "git init failed"
    git remote add origin "$REPO_URL" >>"$REPORT" 2>&1 || fail "git remote add origin failed"
else
    log "INFO: /opt/languagetools is already a git repo."
fi

git remote set-url origin "$REPO_URL" >>"$REPORT" 2>&1 || fail "Could not set origin URL"

log ""
log "=== CHECK GITHUB AUTH ==="

if command -v gh >/dev/null 2>&1; then
    gh auth status >>"$REPORT" 2>&1
    if [ $? -eq 0 ]; then
        log "INFO: gh auth status passed"
    else
        log "WARNING: gh auth status failed. Git push may fail."
    fi
else
    log "WARNING: gh command not found."
fi

log ""
log "=== ABORT LEFTOVER REBASE IF PRESENT ==="

if [ -d ".git/rebase-merge" ] || [ -d ".git/rebase-apply" ]; then
    log "WARNING: Found leftover rebase state."
    git status --short --branch | tee -a "$REPORT"

    git rebase --abort >>"$REPORT" 2>&1 || true

    if [ -d ".git/rebase-merge" ] || [ -d ".git/rebase-apply" ]; then
        log "WARNING: Rebase metadata still exists. Moving to backup."
        mkdir -p "$BACKUP_DIR/languagetools-rebase-state-$STAMP"

        [ -d ".git/rebase-merge" ] && mv ".git/rebase-merge" "$BACKUP_DIR/languagetools-rebase-state-$STAMP/rebase-merge"
        [ -d ".git/rebase-apply" ] && mv ".git/rebase-apply" "$BACKUP_DIR/languagetools-rebase-state-$STAMP/rebase-apply"
    fi
else
    log "INFO: No leftover rebase state found."
fi

log ""
log "=== FETCH REMOTE ==="

git fetch origin --prune >>"$REPORT" 2>&1 || fail "git fetch origin --prune failed"

DEFAULT_BRANCH="$(git remote show origin 2>>"$REPORT" | awk '/HEAD branch/ {print $NF}' | tail -n 1)"
[ -n "$DEFAULT_BRANCH" ] || DEFAULT_BRANCH="main"

log "INFO: Default branch appears to be: $DEFAULT_BRANCH"

log ""
log "=== CHECKOUT DEFAULT BRANCH ==="

if git show-ref --verify --quiet "refs/heads/$DEFAULT_BRANCH"; then
    git checkout "$DEFAULT_BRANCH" >>"$REPORT" 2>&1 || fail "Could not checkout $DEFAULT_BRANCH"
else
    git checkout -B "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH" >>"$REPORT" 2>&1 \
        || fail "Could not create local $DEFAULT_BRANCH from origin/$DEFAULT_BRANCH"
fi

log ""
log "=== UPDATE CODE VERSION ==="

date '+%Y-%m-%d %H:%M:%S %Z' > code-version.txt

log "INFO: Updated /opt/languagetools/code-version.txt"

log ""
log "=== PUBLIC SECRET SCAN ==="

SCAN_HITS="$CONFIDENTIAL_DIR/direct-secret-scan-$STAMP.txt"

grep -RInE \
    '(password\s*=|passwd\s*=|secret\s*=|api[_-]?key|token\s*=|authorization:|bearer |PRIVATE KEY|BEGIN RSA PRIVATE KEY|BEGIN OPENSSH PRIVATE KEY)' \
    "$PROJECT_DIR" \
    --exclude-dir=".git" \
    --exclude="Vn57Ho6S.txt" \
    --exclude="direct_publish_repair.sh" \
    --exclude="*.log" \
    > "$SCAN_HITS" 2>/dev/null || true

if [ -s "$SCAN_HITS" ]; then
    log "PROBLEM: Possible sensitive content found."
    log "Review this file before pushing: $SCAN_HITS"
    head -20 "$SCAN_HITS" | tee -a "$REPORT"
    fail "Stopped before push because possible secrets were detected."
fi

log "INFO: No obvious sensitive content patterns found."

log ""
log "=== STATUS BEFORE COMMIT ==="

git status --short --branch | tee -a "$REPORT"

log ""
log "=== STAGE AND COMMIT FROM /opt/languagetools ==="

git add -A >>"$REPORT" 2>&1 || fail "git add -A failed"

# Make sure the local marker/script do not get committed.
git reset -- Vn57Ho6S.txt direct_publish_repair.sh >>"$REPORT" 2>&1 || true

if git diff --cached --quiet; then
    log "INFO: No staged changes to commit."
else
    git commit -m "Direct LanguageTools publish $STAMP" >>"$REPORT" 2>&1 \
        || fail "git commit failed"
    log "INFO: Commit created."
fi

log ""
log "=== REBASE FROM ORIGIN/$DEFAULT_BRANCH ==="

git pull --rebase origin "$DEFAULT_BRANCH" >>"$REPORT" 2>&1
PULL_RC=$?

if [ $PULL_RC -ne 0 ]; then
    log "PROBLEM: git pull --rebase failed."
    git status --short --branch | tee -a "$REPORT"
    git rebase --abort >>"$REPORT" 2>&1 || true
    fail "Rebase failed. See report: $REPORT"
fi

log "INFO: Rebase succeeded."

log ""
log "=== PUSH FROM /opt/languagetools ==="

git push -u origin "$DEFAULT_BRANCH" >>"$REPORT" 2>&1
PUSH_RC=$?

if [ $PUSH_RC -ne 0 ]; then
    log "PROBLEM: git push failed."
    log "Manual check:"
    log "cd /opt/languagetools"
    log "git status --short --branch"
    log "git remote -v"
    log "git push -u origin $DEFAULT_BRANCH"
    fail "Push failed. See report: $REPORT"
fi

log "INFO: git push succeeded."

write_marker_success

log ""
log "=== SUCCESS MARKER WRITTEN ==="
log "Marker file: $MARKER_FILE"
log "Marker text: $SUCCESS_TEXT"

log ""
log "========================================"
log "DONE: Direct publish from /opt/languagetools completed successfully."
log "Report saved to: $REPORT"
log "========================================"

exit 0
