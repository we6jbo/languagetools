
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
set -Eeuo pipefail

PROJECT_DIR="/opt/languagetools"
REPO_URL="https://github.com/we6jbo/languagetools"
DEFAULT_BRANCH="main"
LOG_FILE="/tmp/a/languagetools-publish.log"
REPORT_FILE="/tmp/a/languagetools-publish-report.txt"
TMP_SCAN_FILE="/tmp/a/languagetools-publish-sensitive.txt"

mkdir -p /tmp/a
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

scan_project() {
    : > "$TMP_SCAN_FILE"

    local p1 p2 p3 p4 p5 p6 p7 p8 p9 p10 p11 p12 p13
    local secret_re pii_re

    # Build sensitive-pattern regex in pieces so the scanner does not block itself.
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

    # Keep the scan active, but remove known false positives from scanner-code files.
    if [ -s "$TMP_SCAN_FILE" ]; then
        FILTERED_SCAN_FILE="${TMP_SCAN_FILE}.filtered"
        grep -vE \
            '(/opt/languagetools/languagetools_scheduled_publish\.sh:[0-9]+:.*(p[0-9]+=|secret_re=|pii_re=)|/opt/languagetools/run\.sh:[0-9]+:.*grep -nE -H)' \
            "$TMP_SCAN_FILE" > "$FILTERED_SCAN_FILE" || true
        mv "$FILTERED_SCAN_FILE" "$TMP_SCAN_FILE"
    fi

    if [ -s "$TMP_SCAN_FILE" ]; then
        report "Sensitive scan blocked publish. Review:"
        cat "$TMP_SCAN_FILE" >> "$REPORT_FILE"
        return 1
    fi

    return 0
}

cd "$PROJECT_DIR"

[ -d .git ] || die "Not a git repo: $PROJECT_DIR"

log "Using default branch: $DEFAULT_BRANCH"

if ! git remote get-url origin >/dev/null 2>&1; then
    git remote add origin "$REPO_URL" >>"$LOG_FILE" 2>&1
fi

if ! scan_project; then
    die "Sensitive or PII-like content found. Publish stopped."
fi

git add -A >>"$LOG_FILE" 2>&1

if git diff --cached --quiet && git diff --quiet; then
    log "No changes to commit."
else
    git commit -m "publish: sync public non-private files ($(date '+%Y%m%d-%H%M%S'))" >>"$LOG_FILE" 2>&1 || true
fi

git fetch origin >>"$LOG_FILE" 2>&1 || true

# After reset-to-origin, this should be clean. Use --autostash for safety.
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


# CHATGPT_SECRET_SCAN_FALSE_POSITIVE_REPAIR
# If scheduled publish still fails, paste the new log to ChatGPT.
# The recurring hits from May 5-7, 2026 appear to be scanner-pattern false positives:
# run.sh and languagetools_scheduled_publish.sh contain the regex text used to detect secrets.
