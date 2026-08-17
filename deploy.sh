#!/usr/bin/env bash
# Sync site assets into .deploy and publish to Quick.
# Usage: ./deploy.sh [subdomain]   (default: screen-notes)
set -euo pipefail
cd "$(dirname "$0")"

SUBDOMAIN="${1:-screen-notes}"

mkdir -p .deploy/notes
cp index.html favicon.png favicon.svg people-directory.json .deploy/
cp notes/*.jpg .deploy/notes/

quick deploy .deploy "$SUBDOMAIN" <<< "y"
