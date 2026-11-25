# source して使う。これ以降の標準出力と標準エラーを、画面に加えて .cache/<名前>.log にも書く。
# 検証者が手元で実行した結果を、あとからエージェントが読めるようにするためのもの。
# ログは追記で、ライセンスキーの形（英数字 4 桁 × 5 組）の文字列は伏せ字にする。
# 使い方: source "$ROOT/scripts/lib/log.sh"; start_log "$ROOT" up

start_log() {
  local root="$1" name="$2"
  local log="$root/.cache/$name.log"
  mkdir -p "$root/.cache"
  printf '\n===== %s %s =====\n' "$name" "$(date '+%Y-%m-%d %H:%M:%S %z')" >>"$log"
  exec > >(tee >(sed -E \
    's/(^|[^A-Za-z0-9])[A-Za-z0-9]{4}(-[A-Za-z0-9]{4}){4}([^A-Za-z0-9]|$)/\1[REDACTED]\3/g' \
    >>"$log")) 2>&1
}
