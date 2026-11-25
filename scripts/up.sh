#!/usr/bin/env bash
# 立ち上げ: AWS のリソースの作成から Tableau Server の起動までを通しで行う。
# 途中で失敗したら、もう一度実行すれば続きから進む。
# 構成は環境変数 TOPOLOGY で選ぶ（single = 単一ノード構成、multi = マルチノード構成）。
# 指定しなければ、いま立っている環境の構成、それもなければ single になる。
set -euo pipefail
export AWS_PAGER=""  # aws CLI の出力をページャーで止めない

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/log.sh"
source "$ROOT/scripts/lib/topology.sh"
start_log "$ROOT" up  # 出力を .cache/up.log にも残す
TOPOLOGY="$(resolve_topology "$ROOT")"
export TOPOLOGY
echo "構成: ${TOPOLOGY}"
CONTEXT="${KUBE_CONTEXT:-tableau-prebuilt}"

cd "$ROOT/terraform"
terraform init -input=false >/dev/null
terraform plan -input=false -var "topology=${TOPOLOGY}" -out=eks.tfplan
read -r -p "この plan を適用しますか？ (yes で適用): " answer
[ "$answer" = "yes" ] || { echo "中止しました。"; exit 1; }
terraform apply -input=false eks.tfplan

aws eks update-kubeconfig --region "$(terraform output -raw region)" \
  --name "$(terraform output -raw cluster_name)" --alias "$CONTEXT" >/dev/null
kubectl --context "$CONTEXT" wait node --all --for=condition=Ready --timeout=10m
kubectl --context "$CONTEXT" apply -f "$ROOT/k8s/storageclass-gp3.yaml"

"$ROOT/scripts/deploy.sh"
