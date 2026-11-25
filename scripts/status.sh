#!/usr/bin/env bash
# Shows the cluster status: Pods, the list of Tableau nodes, and the process status on each node.
# The worker Pods have no health check, so check here, not the Pod status, to see whether they joined.
set -euo pipefail

CONTEXT="${KUBE_CONTEXT:-tableau-prebuilt}"
NAMESPACE="${NAMESPACE:-tableau}"
RELEASE="${RELEASE:-tableau}"
POD="${RELEASE}-tableau-server-primary-0"
K="kubectl --context $CONTEXT -n $NAMESPACE"

echo "== Pod =="
$K get pods -o wide
echo "== Tableau nodes =="
$K exec "$POD" -c tableau-server -- bash -lc 'tsm topology list-nodes -v'
echo "== Process status =="
$K exec "$POD" -c tableau-server -- bash -lc 'tsm status -v'
