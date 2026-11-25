#!/usr/bin/env bash
# クラスタの状態を表示する: Pod、Tableau のノードの一覧、各ノードのプロセスの状態。
# ワーカーの Pod にはヘルスチェックがないので、参加したかどうかは Pod の状態ではなくここで見る。
set -euo pipefail

CONTEXT="${KUBE_CONTEXT:-tableau-prebuilt}"
NAMESPACE="${NAMESPACE:-tableau}"
RELEASE="${RELEASE:-tableau}"
POD="${RELEASE}-tableau-server-primary-0"
K="kubectl --context $CONTEXT -n $NAMESPACE"

echo "== Pod =="
$K get pods -o wide
echo "== Tableau のノード =="
$K exec "$POD" -c tableau-server -- bash -lc 'tsm topology list-nodes -v'
echo "== プロセスの状態 =="
$K exec "$POD" -c tableau-server -- bash -lc 'tsm status -v'
