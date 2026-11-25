#!/usr/bin/env bash
# Forwards local port 8080 to the Tableau Server gateway (port 8080 on the Pod).
# http://localhost:8080 works only while this is running. Stop it with Ctrl-C.
# The chart's Service does not expose port 8080, so this connects to the Pod directly.
set -euo pipefail

CONTEXT="${KUBE_CONTEXT:-tableau-prebuilt}"
NAMESPACE="${NAMESPACE:-tableau}"
RELEASE="${RELEASE:-tableau}"

echo "Open http://localhost:8080 (press Ctrl-C to stop)"
exec kubectl --context "$CONTEXT" -n "$NAMESPACE" port-forward \
  --address 127.0.0.1 "pod/${RELEASE}-tableau-server-primary-0" 8080:8080
