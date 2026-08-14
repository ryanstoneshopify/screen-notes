#!/bin/bash
# Refreshes users.json (all active Shopify employees) from BigQuery and deploys
# the site from a clean checkout of latest main — never the local working tree.
#
# Usage:
#   ./update-users.sh            # refresh users.json in this directory only
#   ./update-users.sh --deploy   # clean-clone main, refresh users.json, deploy
#
# Scheduled daily via launchd (com.ryanstone.screen-notes-users.plist).
set -euo pipefail

REPO_URL="https://github.com/ryanstoneshopify/screen-notes.git"
SUBDOMAIN="screen-notes"

generate_users() {
  local target_dir="$1"
  echo "[update-users] querying BigQuery…"
  bq query --nouse_legacy_sql --format=json --max_rows=20000 "
    SELECT o.full_name AS name, LOWER(o.email) AS email,
           s.user_id AS slack_id, s.user_name AS slack_handle
    FROM \`shopify-dw.people.okta_employees_v1\` o
    JOIN \`shopify-dw.people.slack_users\` s
      ON LOWER(s.email) = LOWER(o.email) AND NOT s.is_deleted AND NOT s.is_bot
    WHERE o.approved
    ORDER BY o.full_name
  " > /tmp/screen-notes-users-raw.json

  # Avatar/title enrichment from artifact's identity dump (public CDN image URLs)
  quick curl https://artifact.quick.shopify.io/users.json > /tmp/screen-notes-users-artifact.json 2>/dev/null || echo -n > /tmp/screen-notes-users-artifact.json

  node -e "
  const fs = require('fs');
  const parseNd = (t) => t.split('\n').filter(l => l.trim()).map(l => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean);
  const rows = JSON.parse(fs.readFileSync('/tmp/screen-notes-users-raw.json', 'utf8'));
  const extraRows = parseNd(fs.readFileSync('/tmp/screen-notes-users-artifact.json', 'utf8'));
  const extra = new Map(extraRows.map(p => [(p.email || '').toLowerCase(), p]));
  const seen = new Set();
  const out = [];
  rows.forEach(r => {
    const email = (r.email || '').toLowerCase();
    if (!email || seen.has(email)) return;
    seen.add(email);
    const e = extra.get(email) || {};
    out.push(JSON.stringify({ name: r.name || email, email, slack_id: r.slack_id || e.slack_id || null, slack_handle: r.slack_handle || e.slack_handle || null, image: e.slack_image_url || null, title: e.title || null }));
  });
  extraRows.forEach(p => {
    const email = (p.email || '').toLowerCase();
    if (!email || seen.has(email)) return;
    seen.add(email);
    out.push(JSON.stringify({ name: p.name || email, email, slack_id: p.slack_id || null, slack_handle: p.slack_handle || null, image: p.slack_image_url || null, title: p.title || null }));
  });
  if (out.length < 1000) { console.error('[update-users] suspiciously few rows (' + out.length + '), aborting'); process.exit(1); }
  fs.writeFileSync('$target_dir/users.json', out.join('\n'));
  console.log('[update-users] wrote users.json with', out.length, 'people,', out.filter(l => l.includes('cdn.shopify.com')).length, 'with avatars');
  "
}

if [[ "${1:-}" == "--deploy" ]]; then
  # Deploy from a pristine clone of latest main, independent of any working tree
  DEPLOY_DIR="$(mktemp -d /tmp/screen-notes-deploy.XXXXXX)"
  trap 'rm -rf "$DEPLOY_DIR"' EXIT
  echo "[update-users] cloning latest main…"
  git clone --depth 1 --branch main "$REPO_URL" "$DEPLOY_DIR/repo"
  generate_users "$DEPLOY_DIR/repo"
  rm -rf "$DEPLOY_DIR/repo/.git"
  echo "[update-users] deploying…"
  quick deploy "$DEPLOY_DIR/repo" "$SUBDOMAIN" <<< "y"
  echo "[update-users] done: $(date)"
else
  cd "$(dirname "$0")"
  generate_users "$(pwd)"
fi
