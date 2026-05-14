#!/usr/bin/env bash
set -u

PROJECT_DIR="/opt/languagetools"
SCRIPT="$PROJECT_DIR/languagetools_scheduled_publish.sh"

echo "RUN.SH HANDOFF $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "Fix made: run.sh calls the scheduled publish script from /opt/languagetools."
echo "Important: this wrapper does not cd into /tmp and does not create a /tmp publish repo."
echo "PWD before exec: $(pwd)"

if [ ! -x "$SCRIPT" ]; then
  echo "FAIL: scheduled publish script is missing or not executable: $SCRIPT"
  exit 1
fi

exec "$SCRIPT"
