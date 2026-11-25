#!/usr/bin/env bash
# Installs Tableau Server from the prebuilt image onto EKS with the official Helm chart.
# Prerequisites: terraform apply is done, the kubeconfig has the context "tableau-prebuilt",
#       Secrets Manager holds the license key and the initial admin password,
#       k8s/reg-info.local.json exists (copy k8s/reg-info.example.json and fill it in).
# Choose the topology with the TOPOLOGY environment variable (single / multi). If unset, it follows the environment that is up.
# Both topologies use the prebuilt image from Docker Hub as is.
# The Setup Tool tar.gz is used only as the source of the official Helm chart; the build scripts are not extracted.
set -euo pipefail
export AWS_PAGER=""  # keep the aws CLI from pausing output in a pager

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/log.sh"
source "$ROOT/scripts/lib/topology.sh"
start_log "$ROOT" deploy  # also save the output to .cache/deploy.log
TOPOLOGY="$(resolve_topology "$ROOT")"
echo "Topology: ${TOPOLOGY}"
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

# 1. Download the chart and verify its checksum (it is not committed to the repository)
mkdir -p "$CACHE"
[ -f "$TARBALL" ] || curl -fsSL -o "$TARBALL" "$URL"
echo "${SHA256}  ${TARBALL}" | shasum -a 256 -c - >/dev/null \
  || { echo "Checksum mismatch: $TARBALL" >&2; exit 1; }
[ -d "$CHART" ] || tar -xzf "$TARBALL" -C "$CACHE" \
  "tableau-server-container-setup-tool-${VERSION}/helm/tableau-server"

[ -f "$REG_INFO" ] || { echo "$REG_INFO not found. Copy k8s/reg-info.example.json and fill it in." >&2; exit 1; }

# 2. Read the secrets from Secrets Manager and pass them to helm on stdin (never in files or arguments)
secret() {
  aws secretsmanager get-secret-value --region "$REGION" \
    --secret-id "$NAME/$1" --query SecretString --output text
}

# Values per topology. This repository's overrides are layered on top of the values bundled with the chart.
K="kubectl --context $CONTEXT -n $NAMESPACE"
POD="${RELEASE}-tableau-server-primary-0"
if [ "$TOPOLOGY" = "multi" ]; then
  # Terraform creates the EFS file system for the bootstrap volume. Read its ID and the mount target IP from the outputs.
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

# 3. Wait until the Pod is Ready (initialization takes 10 to 20 minutes in the single-node topology; not measured for multi-node)
# kubectl wait can return success immediately by looking at an old Pod that is terminating during a recreate, so wait with rollout status.
echo "Waiting for the initial node's Pod to be Ready (up to 90 minutes)..."
$K rollout status "statefulset/${RELEASE}-tableau-server-primary" --timeout=90m

if [ "$TOPOLOGY" = "multi" ]; then
  $K rollout status "statefulset/${RELEASE}-tableau-server-worker" --timeout=30m
  # The worker Pods have no health check, so the Pod status does not show whether they joined.
  # Check with tsm until three nodes are registered in the cluster (up to 30 minutes).
  EXPECTED=3
  echo "Waiting for ${EXPECTED} Tableau nodes to be registered..."
  nodes=0
  for _ in $(seq 1 60); do
    nodes="$($K exec "$POD" -c tableau-server -- bash -lc 'tsm topology list-nodes -v' 2>/dev/null | grep -c '^node' || true)"
    [ "$nodes" -eq "$EXPECTED" ] && break
    sleep 30
  done
  "$ROOT/scripts/status.sh"
  [ "$nodes" -eq "$EXPECTED" ] || { echo "${nodes} nodes are registered (expected ${EXPECTED})." >&2; exit 1; }
  echo "${EXPECTED} nodes are registered."
else
  $K get pods -o wide
fi
