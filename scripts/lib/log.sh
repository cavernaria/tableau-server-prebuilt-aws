# Source this file. From then on, stdout and stderr go to .cache/<name>.log as well as the terminal.
# This keeps a record of each run so it can be reviewed later.
# The log is appended to, and strings shaped like a license key (five groups of four alphanumerics) are redacted.
# Usage: source "$ROOT/scripts/lib/log.sh"; start_log "$ROOT" up

start_log() {
  local root="$1" name="$2"
  local log="$root/.cache/$name.log"
  mkdir -p "$root/.cache"
  printf '\n===== %s %s =====\n' "$name" "$(date '+%Y-%m-%d %H:%M:%S %z')" >>"$log"
  exec > >(tee >(sed -E \
    's/(^|[^A-Za-z0-9])[A-Za-z0-9]{4}(-[A-Za-z0-9]{4}){4}([^A-Za-z0-9]|$)/\1[REDACTED]\3/g' \
    >>"$log")) 2>&1
}
