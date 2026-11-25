#!/usr/bin/env bash
# Tableau Server が使えるかを、ブラウザを使わずに REST API で確かめる。
# 初期管理者でログインし、ワークブックの数を数え、ビューを 1 つ画像で描画する。
# Pod の作り直しや構成の変更の前後で、同じ結果になるかを比べるために使う。
# 使い方: ./scripts/check-view.sh [画像の保存先]
set -euo pipefail
export AWS_PAGER=""

NAME="${NAME:-tableau-prebuilt}"
REGION="${AWS_REGION:-ap-northeast-1}"
CONTEXT="${KUBE_CONTEXT:-tableau-prebuilt}"
NAMESPACE="${NAMESPACE:-tableau}"
RELEASE="${RELEASE:-tableau}"
PORT="${PORT:-18080}"  # connect.sh の 8080 番とぶつからないようにする
OUT="${1:-/dev/null}"
API="http://localhost:${PORT}/api/3.30"

W="$(mktemp -d)"
kubectl --context "$CONTEXT" -n "$NAMESPACE" port-forward --address 127.0.0.1 \
  "pod/${RELEASE}-tableau-server-primary-0" "${PORT}:8080" >/dev/null 2>&1 &
PF=$!
trap 'kill "$PF" 2>/dev/null || true; rm -rf "$W"' EXIT
sleep 4

# パスワードは Secrets Manager から取り、標準入力で curl に渡す（引数にも画面にも出さない）
aws secretsmanager get-secret-value --region "$REGION" \
  --secret-id "$NAME/admin-password" --query SecretString --output text |
  jq -Rs '{credentials: {name: "admin", password: rtrimstr("\n"), site: {contentUrl: ""}}}' |
  curl -s -H 'Accept: application/json' -H 'Content-Type: application/json' \
    --data @- "$API/auth/signin" >"$W/signin.json"
TOKEN="$(jq -r '.credentials.token // empty' "$W/signin.json")"
SITE="$(jq -r '.credentials.site.id // empty' "$W/signin.json")"
[ -n "$TOKEN" ] || { echo "ログイン: 失敗 $(jq -c '.error' "$W/signin.json" 2>/dev/null)" >&2; exit 1; }
echo "ログイン: 成功"

get() { curl -s -H 'Accept: application/json' -H "X-Tableau-Auth: $TOKEN" "$API/sites/$SITE/$1"; }

get workbooks | jq -r '.workbooks.workbook // [] | "ワークブック: \(length) 個（\(map(.name) | join(", "))）"'
VIEW="$(get views | jq -r '.views.view // [] | (map(select(.name == "Overview"))[0] // .[0]) | .id // empty')"
[ -n "$VIEW" ] || { echo "ビューがありません。" >&2; exit 1; }

START="$(date +%s)"
CODE="$(curl -s -H "X-Tableau-Auth: $TOKEN" -o "$W/view.png" -w '%{http_code}' \
  "$API/sites/$SITE/views/$VIEW/image?maxAge=1")"
SIZE="$(wc -c <"$W/view.png" | tr -d ' ')"
echo "ビューの描画: http=${CODE} ${SIZE} バイト（$(( $(date +%s) - START )) 秒）"
[ "$OUT" = /dev/null ] || cp "$W/view.png" "$OUT"
curl -s -o /dev/null -X POST -H "X-Tableau-Auth: $TOKEN" "$API/auth/signout"
[ "$CODE" = 200 ] && [ "$SIZE" -gt 10000 ]
