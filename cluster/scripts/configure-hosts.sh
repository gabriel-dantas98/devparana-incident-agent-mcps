#!/bin/bash

set -euo pipefail

REQUIRED_BASE_HOST="localdev.me"
REQUIRED_SERVICE_HOSTS=(
  "argocd.localdev.me"
  "backstage.localdev.me"
  "grafana.localdev.me"
  "prometheus.localdev.me"
)

HOSTS_FILE="/etc/hosts"

if [ ! -w "$HOSTS_FILE" ]; then
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "This script needs to modify $HOSTS_FILE. Re-running with sudo..."
    exec sudo "$0" "$@"
  fi
fi

is_present() {
  local host="$1"
  grep -Ev '^#' "$HOSTS_FILE" | grep -Eq "(^|\s)${host}(\s|$)"
}

add_line() {
  local line="$1"
  echo "$line" >> "$HOSTS_FILE"
  echo "Added: $line"
}

# Ensure base host
if ! is_present "$REQUIRED_BASE_HOST"; then
  add_line "127.0.0.1   ${REQUIRED_BASE_HOST}"
else
  echo "Present: ${REQUIRED_BASE_HOST}"
fi

# Ensure service hosts (add missing ones in one line)
MISSING_SERVICE_HOSTS=()
for h in "${REQUIRED_SERVICE_HOSTS[@]}"; do
  if ! is_present "$h"; then
    MISSING_SERVICE_HOSTS+=("$h")
  else
    echo "Present: $h"
  fi
done

if [ ${#MISSING_SERVICE_HOSTS[@]} -gt 0 ]; then
  add_line "127.0.0.1   ${MISSING_SERVICE_HOSTS[*]}"
else
  echo "All service hosts present."
fi

echo "Done."
