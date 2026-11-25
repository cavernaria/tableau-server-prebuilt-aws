#!/usr/bin/env bash
# Bring up: runs everything from creating the AWS resources to starting Tableau Server.
# If it fails partway, run it again and it continues from where it stopped.
# Choose the topology with the TOPOLOGY environment variable (single = single-node, multi = multi-node).
# If unset, it follows the environment that is up, or single if there is none.
set -euo pipefail
export AWS_PAGER=""  # keep the aws CLI from pausing output in a pager

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/log.sh"
source "$ROOT/scripts/lib/topology.sh"
start_log "$ROOT" up  # also save the output to .cache/up.log
TOPOLOGY="$(resolve_topology "$ROOT")"
export TOPOLOGY
echo "Topology: ${TOPOLOGY}"
CONTEXT="${KUBE_CONTEXT:-tableau-prebuilt}"

cd "$ROOT/terraform"
terraform init -input=false >/dev/null
terraform plan -input=false -var "topology=${TOPOLOGY}" -out=eks.tfplan
read -r -p "Apply this plan? (type yes to apply): " answer
[ "$answer" = "yes" ] || { echo "Aborted."; exit 1; }
terraform apply -input=false eks.tfplan

aws eks update-kubeconfig --region "$(terraform output -raw region)" \
  --name "$(terraform output -raw cluster_name)" --alias "$CONTEXT" >/dev/null
kubectl --context "$CONTEXT" wait node --all --for=condition=Ready --timeout=10m
kubectl --context "$CONTEXT" apply -f "$ROOT/k8s/storageclass-gp3.yaml"

# On the first run the secrets have no values yet, and deploy.sh stops here and says so.
# Set the values, then run this script again.
"$ROOT/scripts/deploy.sh"
echo "Elapsed (up): $((SECONDS / 60)) min $((SECONDS % 60)) s"
