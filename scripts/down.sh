#!/usr/bin/env bash
# Teardown: deactivate the license → remove Tableau Server → delete the AWS resources → check for leftovers.
# If it fails partway, run it again and it continues from where it stopped.
# Set FORCE=1 only when you want to continue even if deactivation fails.
set -euo pipefail
export AWS_PAGER=""  # keep the aws CLI from pausing output in a pager

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/log.sh"
start_log "$ROOT" down  # also save the output to .cache/down.log
NAME="${NAME:-tableau-prebuilt}"
REGION="${AWS_REGION:-ap-northeast-1}"
CONTEXT="${KUBE_CONTEXT:-tableau-prebuilt}"
NAMESPACE="${NAMESPACE:-tableau}"
RELEASE="${RELEASE:-tableau}"
POD="${RELEASE}-tableau-server-primary-0"
K="kubectl --context $CONTEXT -n $NAMESPACE"

cat <<MSG
The following will be deleted (this cannot be undone).
  - Tableau Server (namespace: ${NAMESPACE}) and the EBS volumes that hold its data
  - The EKS cluster, instances, VPC, NAT Gateway, and Elastic IP
  - In the multi-node topology, the EFS file system for the bootstrap volume (including the bootstrap file)
  - The Secrets Manager secrets (license key, initial admin password) and the KMS key
The license is deactivated before deletion.
MSG
read -r -p "Continue? (type yes to continue): " answer
[ "$answer" = "yes" ] || { echo "Aborted."; exit 1; }

if kubectl --context "$CONTEXT" get ns "$NAMESPACE" >/dev/null 2>&1; then
  # 1. Deactivate the license (the key is read from the Pod's environment and never shown)
  if $K get pod "$POD" >/dev/null 2>&1; then
    echo "Deactivating the license..."
    if ! $K exec "$POD" -- bash -lc 'tsm licenses deactivate --license-key "$LICENSE_KEY"'; then
      [ "${FORCE:-0}" = "1" ] || { echo "Deactivation failed. Find the cause, or run again with FORCE=1." >&2; exit 1; }
      echo "Deactivation failed, but continuing because FORCE=1 is set." >&2
    fi
  fi
  # 2. Remove Tableau Server and its volumes (helm does not delete PVCs, so delete them explicitly)
  helm --kube-context "$CONTEXT" -n "$NAMESPACE" uninstall "$RELEASE" --wait 2>/dev/null || true
  $K delete pvc --all --wait=true
  # The bootstrap PV in the multi-node topology is Retain, so delete it if it remains. Its contents go away with the EFS in terraform destroy.
  kubectl --context "$CONTEXT" delete pv -l "app.kubernetes.io/instance=${RELEASE},app.kubernetes.io/name=tableau-server" --ignore-not-found --wait=true
  kubectl --context "$CONTEXT" delete ns "$NAMESPACE" --wait=true
else
  echo "Cannot reach the cluster, or the namespace does not exist. Skipping the removal of Tableau Server."
fi

# 3. Delete the AWS resources (terraform asks for confirmation)
cd "$ROOT/terraform"
terraform destroy -input=false

# 4. Check that nothing is left
"$ROOT/scripts/check-leftovers.sh"
