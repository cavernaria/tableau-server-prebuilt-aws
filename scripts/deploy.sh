#!/usr/bin/env bash
# プレビルトイメージの Tableau Server を、公式 Helm チャートで EKS に入れる。
# 前提: terraform apply 済み、kubeconfig に context "tableau-prebuilt" がある、
#       Secrets Manager にライセンスキーと初期管理者パスワードが入っている、
#       k8s/reg-info.local.json がある（k8s/reg-info.example.json を写して埋める）。
# 構成は環境変数 TOPOLOGY で選ぶ（single / multi）。指定しなければ、立っている環境の構成に合わせる。
# イメージはどちらの構成でも Docker Hub のプレビルトイメージをそのまま使う。
# Setup Tool の tar.gz は公式 Helm チャートの入手元としてだけ使い、ビルド用のスクリプトは取り出さない。
set -euo pipefail
export AWS_PAGER=""  # aws CLI の出力をページャーで止めない

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/log.sh"
source "$ROOT/scripts/lib/topology.sh"
start_log "$ROOT" deploy  # 出力を .cache/deploy.log にも残す
TOPOLOGY="$(resolve_topology "$ROOT")"
echo "構成: ${TOPOLOGY}"
NAME="${NAME:-tableau-prebuilt}"
REGION="${AWS_REGION:-ap-northeast-1}"
CONTEXT="${KUBE_CONTEXT:-tableau-prebuilt}"
NAMESPACE="${NAMESPACE:-tableau}"
RELEASE="${RELEASE:-tableau}"

VERSION="2026.3.0"
URL="https://downloads.tableau.com/esdalt/${VERSION}/tableau-server-container-setup-tool-${VERSION}.tar.gz"
SHA256="fb16e44bb511ab3d7cb3506442fbe62d600c6a806d02fcf036e494b2ceaf36d6"
CACHE="$ROOT/.cache/setup-tool-${VERSION}"
TARBALL="$CACHE/setup-tool.tar.gz"
CHART="$CACHE/tableau-server-container-setup-tool-${VERSION}/helm/tableau-server"
REG_INFO="$ROOT/k8s/reg-info.local.json"

# 1. チャートを取得し、チェックサムを照合する（リポジトリには入れない）
mkdir -p "$CACHE"
[ -f "$TARBALL" ] || curl -fsSL -o "$TARBALL" "$URL"
echo "${SHA256}  ${TARBALL}" | shasum -a 256 -c - >/dev/null \
  || { echo "チェックサムが一致しません: $TARBALL" >&2; exit 1; }
[ -d "$CHART" ] || tar -xzf "$TARBALL" -C "$CACHE" \
  "tableau-server-container-setup-tool-${VERSION}/helm/tableau-server"

[ -f "$REG_INFO" ] || { echo "$REG_INFO がありません。k8s/reg-info.example.json を写して埋めてください。" >&2; exit 1; }

# 2. 秘密情報を Secrets Manager から取り、標準入力で helm に渡す（ファイルにも引数にも残さない）
secret() {
  aws secretsmanager get-secret-value --region "$REGION" \
    --secret-id "$NAME/$1" --query SecretString --output text
}

# 構成ごとの values。チャート同梱の values を土台に、このリポジトリの上書きを重ねる。
K="kubectl --context $CONTEXT -n $NAMESPACE"
POD="${RELEASE}-tableau-server-primary-0"
if [ "$TOPOLOGY" = "multi" ]; then
  # bootstrap ボリューム用の EFS は Terraform が作る。ID とマウントターゲットの IP を出力から取る。
  EFS_ID="$(terraform -chdir="$ROOT/terraform" output -raw efs_file_system_id)"
  EFS_IP="$(terraform -chdir="$ROOT/terraform" output -raw efs_mount_target_ip)"
  HELM_ARGS=(
    -f "$CHART/values-multinode.yaml"
    -f "$ROOT/k8s/values-eks-multi.yaml"
    --set-string "persistence.bootstrap.pv.csi.volumeHandle=${EFS_ID}"
    --set-string "persistence.bootstrap.pv.csi.volumeAttributes.mounttargetip=${EFS_IP}"
  )
else
  HELM_ARGS=(
    -f "$CHART/values-single.yaml"
    -f "$ROOT/k8s/values-eks-single.yaml"
  )
fi

jq -n --arg key "$(secret license-key)" --arg pw "$(secret admin-password)" \
  '{secrets: {licenseKey: $key, tableauPassword: $pw}}' |
  helm upgrade --install "$RELEASE" "$CHART" \
    --kube-context "$CONTEXT" --namespace "$NAMESPACE" --create-namespace \
    "${HELM_ARGS[@]}" \
    -f - \
    --set-file "config.regInfoJson=$REG_INFO" \
    "$@"

# 3. Pod が Ready になるまで待つ（単一ノード構成の初期化は 10〜20 分。マルチノード構成は未計測）
# kubectl wait は、作り直しで終了中の古い Pod を見て即座に成功を返すことがあるので、rollout status で待つ。
echo "初期ノードの Pod の Ready を待ちます（最大 90 分）..."
$K rollout status "statefulset/${RELEASE}-tableau-server-primary" --timeout=90m

if [ "$TOPOLOGY" = "multi" ]; then
  $K rollout status "statefulset/${RELEASE}-tableau-server-worker" --timeout=30m
  # ワーカーの Pod にはヘルスチェックがないので、Pod の状態では参加したか分からない。
  # 3 つのノードがクラスタに登録されるまで、tsm で確かめる（最大 30 分）。
  EXPECTED=3
  echo "Tableau のノードが ${EXPECTED} つ登録されるのを待ちます..."
  nodes=0
  for _ in $(seq 1 60); do
    nodes="$($K exec "$POD" -c tableau-server -- bash -lc 'tsm topology list-nodes -v' 2>/dev/null | grep -c '^node' || true)"
    [ "$nodes" -eq "$EXPECTED" ] && break
    sleep 30
  done
  "$ROOT/scripts/status.sh"
  [ "$nodes" -eq "$EXPECTED" ] || { echo "登録されたノードは ${nodes} つです（期待は ${EXPECTED} つ）。" >&2; exit 1; }
  echo "ノードが ${EXPECTED} つ登録されました。"
else
  $K get pods -o wide
fi
