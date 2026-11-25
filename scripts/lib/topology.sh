# source して使う。構成（single = 単一ノード構成、multi = マルチノード構成）を決める。
# 環境変数 TOPOLOGY があればそれを使う。なければ、いま立っている環境の構成（Terraform の出力）、
# それもなければ single にする。
# 使い方: source "$ROOT/scripts/lib/topology.sh"; TOPOLOGY="$(resolve_topology "$ROOT")"

resolve_topology() {
  local root="$1" t="${TOPOLOGY:-}"
  if [ -n "$t" ]; then
    case "$t" in
      single|multi) echo "$t"; return 0 ;;
      *) echo "TOPOLOGY は single か multi を指定してください: ${t}" >&2; return 1 ;;
    esac
  fi
  t="$(terraform -chdir="$root/terraform" output -raw topology 2>/dev/null || true)"
  case "$t" in
    single|multi) echo "$t" ;;
    *) echo single ;;
  esac
}
