# Source this file. Decides the topology (single = single-node, multi = multi-node).
# Uses the TOPOLOGY environment variable if set. Otherwise the topology of the environment that is up (the Terraform output),
# and single if there is none.
# Usage: source "$ROOT/scripts/lib/topology.sh"; TOPOLOGY="$(resolve_topology "$ROOT")"

resolve_topology() {
  local root="$1" t="${TOPOLOGY:-}"
  if [ -n "$t" ]; then
    case "$t" in
      single|multi) echo "$t"; return 0 ;;
      *) echo "TOPOLOGY must be single or multi: ${t}" >&2; return 1 ;;
    esac
  fi
  t="$(terraform -chdir="$root/terraform" output -raw topology 2>/dev/null || true)"
  case "$t" in
    single|multi) echo "$t" ;;
    *) echo single ;;
  esac
}
