#!/bin/bash
# Regenerates users.json (all active Shopify employees) from BigQuery.
# Usage:
#   ./update-users.sh            # refresh users.json only
#   ./update-users.sh --deploy   # refresh + deploy the site to quick
#
# Scheduled weekly via launchd (see com.ryanstone.screen-notes-users.plist).
set -euo pipefail
cd "$(dirname "$0")"

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

node -e "
const rows = JSON.parse(require('fs').readFileSync('/tmp/screen-notes-users-raw.json', 'utf8'));
const seen = new Set();
const out = [];
rows.forEach(r => {
  const email = (r.email || '').toLowerCase();
  if (!email || seen.has(email)) return;
  seen.add(email);
  out.push(JSON.stringify({ name: r.name || email, email, slack_id: r.slack_id || null, slack_handle: r.slack_handle || null }));
});
if (out.length < 1000) { console.error('[update-users] suspiciously few rows (' + out.length + '), aborting'); process.exit(1); }
require('fs').writeFileSync('users.json', out.join('\n'));
console.log('[update-users] wrote users.json with', out.length, 'people');
"

if [[ "${1:-}" == "--deploy" ]]; then
  # Only auto-deploy from a clean working tree so scheduled runs never ship WIP
  if [[ -z "$(git status --porcelain --ignore-submodules -- . ':!users.json')" ]]; then
    echo "[update-users] deploying…"
    quick deploy . screen-notes <<< "y"
  else
    echo "[update-users] working tree has uncommitted changes — skipping deploy (users.json refreshed locally)"
  fi
fi
