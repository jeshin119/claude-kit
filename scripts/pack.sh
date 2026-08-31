#!/usr/bin/env bash
# 각 스킬 디렉터리를 dist/<name>.skill 로 압축한다. claude.ai 계정 업로드용.
# 인자로 스킬 이름을 받고, 없으면 전부 압축한다.
#
# 스킬은 플러그인마다 흩어져 있으므로 plugins/*/skills/* 를 전부 훑는다.
# 계정에 올릴 때는 플러그인 경계가 사라지고 스킬 이름만 남는다.
#
# zip 을 우선 쓰고, 없으면 python3 표준 라이브러리(zipfile)로 폴백한다.
# 폴백을 둔 이유: 최소 Docker 이미지에는 zip 이 없는 경우가 많은데, 그때마다
# 패키지를 설치해야 하면 컨테이너에서 못 돌아간다. 둘 다 없을 때만 실패한다.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGINS_ROOT="$REPO/plugins"
DIST="$REPO/dist"

[ -d "$PLUGINS_ROOT" ] || { echo "오류: $PLUGINS_ROOT 가 없다." >&2; exit 1; }

# 이름 하나를 받아 그 스킬의 디렉터리 경로를 낸다. 못 찾으면 1 로 끝낸다.
skill_dir() {
  local d
  for d in "$PLUGINS_ROOT"/*/skills/"$1"/; do
    [ -d "$d" ] && { printf '%s' "${d%/}"; return 0; }
  done
  return 1
}

if command -v zip >/dev/null 2>&1; then
  BACKEND=zip
elif command -v python3 >/dev/null 2>&1; then
  BACKEND=python3
else
  echo "오류: zip 도 python3 도 없다. 'sudo apt install zip' 후 다시 실행한다." >&2
  exit 1
fi

if [ $# -gt 0 ]; then
  names=("$@")
else
  names=()
  for d in "$PLUGINS_ROOT"/*/skills/*/; do
    [ -d "$d" ] && names+=("$(basename "$d")")
  done
fi

[ ${#names[@]} -gt 0 ] || { echo "오류: 압축할 스킬이 없다." >&2; exit 1; }

mkdir -p "$DIST"
echo "압축 백엔드: $BACKEND"

for name in "${names[@]}"; do
  dir="$(skill_dir "$name")" || { echo "오류: 그런 스킬이 없다: $name" >&2; exit 1; }
  root="$(dirname "$dir")"
  out="$DIST/$name.skill"
  rm -f "$out"

  if [ "$BACKEND" = zip ]; then
    ( cd "$root" && zip -q -r "$out" "$name" -x '*.DS_Store' )
  else
    python3 - "$root" "$name" "$out" <<'PY'
import os, sys, zipfile
root, name, out = sys.argv[1], sys.argv[2], sys.argv[3]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for dirpath, dirnames, filenames in os.walk(os.path.join(root, name)):
        dirnames.sort()
        for fn in sorted(filenames):
            if fn == ".DS_Store":
                continue
            full = os.path.join(dirpath, fn)
            z.write(full, os.path.relpath(full, root))
PY
  fi
  echo "압축: $out"
done

echo
echo "claude.ai → Settings → Capabilities 에서 위 파일을 업로드한다."
