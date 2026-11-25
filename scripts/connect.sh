#!/usr/bin/env bash
# 手元の 8080 番を Tableau Server のゲートウェイ（Pod の 8080 番）に転送する。
# 実行している間だけ http://localhost:8080 で使える。Ctrl-C で止める。
# チャートの Service は 8080 番を出していないので、Pod に直接つなぐ。
set -euo pipefail

CONTEXT="${KUBE_CONTEXT:-tableau-prebuilt}"
NAMESPACE="${NAMESPACE:-tableau}"
RELEASE="${RELEASE:-tableau}"

echo "http://localhost:8080 を開いてください（止めるには Ctrl-C）"
exec kubectl --context "$CONTEXT" -n "$NAMESPACE" port-forward \
  --address 127.0.0.1 "pod/${RELEASE}-tableau-server-primary-0" 8080:8080
