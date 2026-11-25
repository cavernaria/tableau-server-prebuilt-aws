#!/usr/bin/env bash
# 削除: ライセンスの認証解除 → Tableau Server の削除 → AWS のリソースの削除 → 残骸の確認。
# 途中で失敗したら、もう一度実行すれば続きから進む。
# 認証解除に失敗しても先へ進めたい場合だけ FORCE=1 を付ける。
set -euo pipefail
export AWS_PAGER=""  # aws CLI の出力をページャーで止めない

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/log.sh"
start_log "$ROOT" down  # 出力を .cache/down.log にも残す
NAME="${NAME:-tableau-prebuilt}"
REGION="${AWS_REGION:-ap-northeast-1}"
CONTEXT="${KUBE_CONTEXT:-tableau-prebuilt}"
NAMESPACE="${NAMESPACE:-tableau}"
RELEASE="${RELEASE:-tableau}"
POD="${RELEASE}-tableau-server-primary-0"
K="kubectl --context $CONTEXT -n $NAMESPACE"

cat <<MSG
次のものを削除します（元に戻せません）。
  - Tableau Server（namespace: ${NAMESPACE}）と、そのデータの入った EBS ボリューム
  - EKS クラスタ、インスタンス、VPC、NAT Gateway、Elastic IP
  - マルチノード構成の場合は、bootstrap ボリューム用の EFS（ブートストラップファイルを含む）
  - Secrets Manager のシークレット（ライセンスキー、初期管理者パスワード）と KMS キー
削除の前に、ライセンスの認証を解除します。
MSG
read -r -p "続けますか？ (yes で続行): " answer
[ "$answer" = "yes" ] || { echo "中止しました。"; exit 1; }

if kubectl --context "$CONTEXT" get ns "$NAMESPACE" >/dev/null 2>&1; then
  # 1. ライセンスの認証を解除する（キーは Pod の環境変数から読み、画面に出さない）
  if $K get pod "$POD" >/dev/null 2>&1; then
    echo "ライセンスの認証を解除します..."
    if ! $K exec "$POD" -- bash -lc 'tsm licenses deactivate --license-key "$LICENSE_KEY"'; then
      [ "${FORCE:-0}" = "1" ] || { echo "認証解除に失敗しました。原因を確かめるか、FORCE=1 を付けて再実行してください。" >&2; exit 1; }
      echo "認証解除に失敗しましたが、FORCE=1 なので続行します。" >&2
    fi
  fi
  # 2. Tableau Server とボリュームを削除する（PVC は helm では消えないので明示的に消す）
  helm --kube-context "$CONTEXT" -n "$NAMESPACE" uninstall "$RELEASE" --wait 2>/dev/null || true
  $K delete pvc --all --wait=true
  # マルチノード構成の bootstrap 用の PV は Retain なので、残っていれば消す。中身は EFS ごと terraform destroy で消える。
  kubectl --context "$CONTEXT" delete pv -l "app.kubernetes.io/instance=${RELEASE},app.kubernetes.io/name=tableau-server" --ignore-not-found --wait=true
  kubectl --context "$CONTEXT" delete ns "$NAMESPACE" --wait=true
else
  echo "クラスタにつながらないか、namespace がありません。Tableau Server の削除は飛ばします。"
fi

# 3. AWS のリソースを削除する（terraform が確認を求める）
cd "$ROOT/terraform"
terraform destroy -input=false

# 4. 残骸がないことを確かめる
"$ROOT/scripts/check-leftovers.sh"
