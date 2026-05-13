#!/usr/bin/env bash
set -Eeuo pipefail

# LanguageTools scheduled publish
# Patched by ChatGPT for Jeremiah O'Neal
# Fix:
# - Shebang is first line.
# - Scan /opt/languagetools.
# - Sync public-safe files into durable publish repo.
# - Commit, rebase, and push ONLY from the publish repo.
# R80A3D995-T2Phal-002-252

CONFIDENTIAL_DIR="/opt/languagetools-confidential"
RUNTIME_DIR="$CONFIDENTIAL_DIR/runtime"
PUBLISH_ROOT="$RUNTIME_DIR/languagetools-publish"
PUBLISH_REPO="$PUBLISH_ROOT/repo"
LOG_DIR="$RUNTIME_DIR/logs"

PROJECT_DIR="/opt/languagetools"
REPO_URL="https://github.com/we6jbo/languagetools"
DEFAULT_BRANCH="main"

LOG_FILE="$LOG_DIR/languagetools-publish.log"
REPORT_FILE="$LOG_DIR/languagetools-publish-report.txt"
TMP_SCAN_FILE="$LOG_DIR/languagetools-publish-sensitive.txt"
SECRET_SCAN_ALLOWLIST="$CONFIDENTIAL_DIR/secret-scan-allowlist.regex"

mkdir -p "$PUBLISH_ROOT" "$LOG_DIR"

: > "$LOG_FILE"
: > "$REPORT_FILE"
: > "$TMP_SCAN_FILE"

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$*" | tee -a "$LOG_FILE"
}

report() {
    printf '%s\n' "$*" >> "$REPORT_FILE"
}

die() {
    log "ERROR: $*"
    report "ERROR: $*"
    exit 1
}

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

scan_project() {
    : > "$TMP_SCAN_FILE"

    local p1 p2 p3 p4 p5 p6 p7 p8 p9 p10 p11 p12 p13
    local secret_re pii_re
    local filtered1 filtered2

    p1='pass''word[[:space:]]*[:=]'
    p2='pass''wd[[:space:]]*[:=]'
    p3='sec''ret[[:space:]]*[:=]'
    p4='client_''secret[[:space:]]*[:=]'
    p5='api[_-]?''key[[:space:]]*[:=]'
    p6='tok''en[[:space:]]*[:=]'
    p7='author''ization:[[:space:]]*bearer[[:space:]]+[A-Za-z0-9._-]+'
    p8='aws_access_''key_id'
    p9='aws_secret_access_''key'
    p10='BEGIN RSA PRIVATE ''KEY'
    p11='BEGIN OPENSSH PRIVATE ''KEY'
    p12='BEGIN PRIVATE ''KEY'
    p13='-----''BEGIN'

    secret_re="(${p1}|${p2}|${p3}|${p4}|${p5}|${p6}|${p7}|${p8}|${p9}|${p10}|${p11}|${p12}|${p13})"
    pii_re='([[:alnum:]._%+-]+@[[:alnum:].-]+\.[A-Za-z]{2,}|([0-9]{3}-[0-9]{2}-[0-9]{4})|((^|[^0-9])([0-9]{3}[- .]?[0-9]{3}[- .]?[0-9]{4})([^0-9]|$)))'

    while IFS= read -r file; do
        [ -f "$file" ] || continue

        case "$file" in
            */.git/*|*/.gitignore|*/code-version.txt)
                continue
                ;;
        esac

        if ! grep -Iq . "$file" 2>/dev/null; then
            continue
        fi

        grep -nE -H "$secret_re" "$file" >> "$TMP_SCAN_FILE" 2>/dev/null || true
        grep -nE -H "$pii_re" "$file" >> "$TMP_SCAN_FILE" 2>/dev/null || true
    done < <(find "$PROJECT_DIR" -type f ! -path '*/.git/*' | sort)

    if [ -s "$TMP_SCAN_FILE" ]; then
        filtered1="${TMP_SCAN_FILE}.filtered1"
        filtered2="${TMP_SCAN_FILE}.filtered2"

        filter_secret_scan_hits "$TMP_SCAN_FILE" > "$filtered1" || true

        grep -vE \
            '(/opt/languagetools/languagetools_scheduled_publish\.sh:[0-9]+:.*(p[0-9]+=|secret_re=|pii_re=|SECRET_SCAN_ALLOWLIST=|filter_secret_scan_hits)|/opt/languagetools/run\.sh:[0-9]+:.*grep -nE -H)' \
            "$filtered1" > "$filtered2" || true

        mv "$filtered2" "$TMP_SCAN_FILE"
        rm -f "$filtered1"
    fi

    if [ -s "$TMP_SCAN_FILE" ]; then
        report "Sensitive scan blocked publish. Review:"
        cat "$TMP_SCAN_FILE" >> "$REPORT_FILE"
        return 1
    fi

    return 0
}

prepare_publish_repo() {
    mkdir -p "$PUBLISH_ROOT"

    if [ ! -d "$PUBLISH_REPO/.git" ]; then
        log "Publish repo missing. Re-cloning: $PUBLISH_REPO"
        rm -rf "$PUBLISH_REPO"
        git clone "$REPO_URL" "$PUBLISH_REPO" >>"$LOG_FILE" 2>&1 || die "Clone failed."
    fi

    cd "$PUBLISH_REPO"

    if ! git remote get-url origin >/dev/null 2>&1; then
        git remote add origin "$REPO_URL" >>"$LOG_FILE" 2>&1
    else
        git remote set-url origin "$REPO_URL" >>"$LOG_FILE" 2>&1
    fi

    if [ -d ".git/rebase-merge" ] || [ -d ".git/rebase-apply" ]; then
        log "Interrupted rebase found. Aborting."
        git rebase --abort >>"$LOG_FILE" 2>&1 || true
    fi

    if [ -f ".git/MERGE_HEAD" ]; then
        log "Interrupted merge found. Aborting."
        git merge --abort >>"$LOG_FILE" 2>&1 || true
    fi

    git fetch origin "$DEFAULT_BRANCH" --prune >>"$LOG_FILE" 2>&1 || die "Fetch failed."

    if git show-ref --verify --quiet "refs/heads/$DEFAULT_BRANCH"; then
        git checkout "$DEFAULT_BRANCH" >>"$LOG_FILE" 2>&1 || die "Checkout main failed."
    else
        git checkout -B "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH" >>"$LOG_FILE" 2>&1 || die "Create main failed."
    fi
}

sync_project_to_publish_repo() {
    cd "$PUBLISH_REPO"

    command -v rsync >/dev/null 2>&1 || die "rsync is not installed."

    log "Syncing from $PROJECT_DIR to $PUBLISH_REPO"

    rsync -a --delete \
        --exclude ".git/" \
        --exclude ".gitignore" \
        --exclude "*confidential*" \
        --exclude "secrets/" \
        --exclude ".env" \
        --exclude "*.pem" \
        --exclude "*.key" \
        --exclude "patch-languagetools-scheduled-publish.sh" \
        "$PROJECT_DIR"/ "$PUBLISH_REPO"/ >>"$LOG_FILE" 2>&1 || die "rsync failed."

    {
        echo "LanguageTools scheduled publish"
        echo "TIME=$(date)"
        echo "HOST=$(hostname)"
        echo "USER=$(id -un)"
        echo "SOURCE_PROJECT=$PROJECT_DIR"
        echo "PUBLISH_REPO=$PUBLISH_REPO"
    } > "$PUBLISH_REPO/code-version.txt"
}

publish_from_publish_repo() {
    cd "$PUBLISH_REPO"

    log "Publishing from PWD=$(pwd)"
    log "Using default branch: $DEFAULT_BRANCH"

    git status --short --branch >>"$LOG_FILE" 2>&1 || true

    git add -A >>"$LOG_FILE" 2>&1

    if git diff --cached --quiet; then
        log "No changes to commit."
    else
        git commit -m "publish: sync public non-private files ($(date '+%Y%m%d-%H%M%S'))" >>"$LOG_FILE" 2>&1 || die "Commit failed."
    fi

    git pull --rebase --autostash origin "$DEFAULT_BRANCH" >>"$LOG_FILE" 2>&1 || die "Rebase failed."
    git push -u origin "$DEFAULT_BRANCH" >>"$LOG_FILE" 2>&1 || die "Push failed."

    LOCAL_HEAD="$(git rev-parse HEAD)"
    REMOTE_HEAD="$(git ls-remote origin "refs/heads/$DEFAULT_BRANCH" | awk '{print $1}')"

    report "LOCAL_HEAD=$LOCAL_HEAD"
    report "REMOTE_HEAD=$REMOTE_HEAD"

    if [ "$LOCAL_HEAD" = "$REMOTE_HEAD" ]; then
        report "VERIFY_RESULT=PASS local HEAD matches origin/$DEFAULT_BRANCH"
        log "VERIFY_RESULT=PASS local HEAD matches origin/$DEFAULT_BRANCH"
        exit 0
    else
        report "VERIFY_RESULT=FAIL local HEAD does not match origin/$DEFAULT_BRANCH"
        die "VERIFY_RESULT=FAIL local HEAD does not match origin/$DEFAULT_BRANCH"
    fi
}

log "========================================"
log "LANGUAGETOOLS SCHEDULED PUBLISH"
log "TIME: $(date)"
log "HOST: $(hostname)"
log "USER: $(id -un)"
log "UID: $(id -u)"
log "START_PWD: $(pwd)"
log "PROJECT_DIR: $PROJECT_DIR"
log "PUBLISH_REPO: $PUBLISH_REPO"
log "========================================"

[ -d "$PROJECT_DIR" ] || die "Project directory missing: $PROJECT_DIR"

if ! scan_project; then
    die "Sensitive or PII-like content found. Publish stopped."
fi

prepare_publish_repo
sync_project_to_publish_repo
publish_from_publish_repo

# CHATGPT_SECRET_SCAN_FALSE_POSITIVE_REPAIR
# If scheduled publish still fails, paste the new log to ChatGPT.
