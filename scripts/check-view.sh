#!/usr/bin/env bash
# Checks that Tableau Server is usable through the REST API, without a browser.
# Signs in as the initial admin, counts the workbooks, and renders one view as an image.
# Use it to compare results before and after recreating a Pod or changing the topology.
# Usage: ./scripts/check-view.sh [image output path]
set -euo pipefail
export AWS_PAGER=""

NAME="${NAME:-tableau-prebuilt}"
REGION="${AWS_REGION:-ap-northeast-1}"
CONTEXT="${KUBE_CONTEXT:-tableau-prebuilt}"
NAMESPACE="${NAMESPACE:-tableau}"
RELEASE="${RELEASE:-tableau}"
PORT="${PORT:-18080}"  # avoid clashing with port 8080 used by connect.sh
OUT="${1:-/dev/null}"
API="http://localhost:${PORT}/api/3.30"

W="$(mktemp -d)"
kubectl --context "$CONTEXT" -n "$NAMESPACE" port-forward --address 127.0.0.1 \
  "pod/${RELEASE}-tableau-server-primary-0" "${PORT}:8080" >/dev/null 2>&1 &
PF=$!
trap 'kill "$PF" 2>/dev/null || true; rm -rf "$W"' EXIT
sleep 4

# The password is read from Secrets Manager and passed to curl on stdin (never in arguments or on screen)
aws secretsmanager get-secret-value --region "$REGION" \
  --secret-id "$NAME/admin-password" --query SecretString --output text |
  jq -Rs '{credentials: {name: "admin", password: rtrimstr("\n"), site: {contentUrl: ""}}}' |
  curl -s -H 'Accept: application/json' -H 'Content-Type: application/json' \
    --data @- "$API/auth/signin" >"$W/signin.json"
TOKEN="$(jq -r '.credentials.token // empty' "$W/signin.json")"
SITE="$(jq -r '.credentials.site.id // empty' "$W/signin.json")"
[ -n "$TOKEN" ] || { echo "Sign-in: failed $(jq -c '.error' "$W/signin.json" 2>/dev/null)" >&2; exit 1; }
echo "Sign-in: succeeded"

get() { curl -s -H 'Accept: application/json' -H "X-Tableau-Auth: $TOKEN" "$API/sites/$SITE/$1"; }

get workbooks | jq -r '.workbooks.workbook // [] | "Workbooks: \(length) (\(map(.name) | join(", ")))"'
VIEW="$(get views | jq -r '.views.view // [] | (map(select(.name == "Overview"))[0] // .[0]) | .id // empty')"
[ -n "$VIEW" ] || { echo "No views found." >&2; exit 1; }

START="$(date +%s)"
CODE="$(curl -s -H "X-Tableau-Auth: $TOKEN" -o "$W/view.png" -w '%{http_code}' \
  "$API/sites/$SITE/views/$VIEW/image?maxAge=1")"
SIZE="$(wc -c <"$W/view.png" | tr -d ' ')"
echo "View render: http=${CODE} ${SIZE} bytes ($(( $(date +%s) - START )) s)"
[ "$OUT" = /dev/null ] || cp "$W/view.png" "$OUT"
curl -s -o /dev/null -X POST -H "X-Tableau-Auth: $TOKEN" "$API/auth/signout"
[ "$CODE" = 200 ] && [ "$SIZE" -gt 10000 ]
