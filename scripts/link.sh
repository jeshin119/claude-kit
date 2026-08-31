#!/usr/bin/env bash
# ~/.claude/CLAUDE.md 를 이 저장소의 shared/CLAUDE.md 로 심링크한다.
# 두 번 실행해도 같은 결과가 되도록 만들었다.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO/shared/CLAUDE.md"
DST="${CLAUDE_HOME:-$HOME/.claude}/CLAUDE.md"

[ -f "$SRC" ] || { echo "오류: $SRC 가 없다." >&2; exit 1; }
mkdir -p "$(dirname "$DST")"

if [ -L "$DST" ]; then
  cur="$(readlink -f "$DST" || true)"
  if [ "$cur" = "$(readlink -f "$SRC")" ]; then
    echo "이미 올바른 심링크다: $DST -> $SRC"
  else
    echo "다른 대상을 가리키는 심링크를 교체한다: $cur"
    ln -sfn "$SRC" "$DST"
    echo "심링크 생성: $DST -> $SRC"
  fi
elif [ -e "$DST" ]; then
  bak="$DST.bak.$(date +%Y%m%d%H%M%S)"
  mv "$DST" "$bak"
  echo "기존 실제 파일을 백업했다: $bak"
  ln -s "$SRC" "$DST"
  echo "심링크 생성: $DST -> $SRC"
else
  ln -s "$SRC" "$DST"
  echo "심링크 생성: $DST -> $SRC"
fi

MANIFEST="$REPO/.claude-plugin/marketplace.json"
MARKET="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["name"])' "$MANIFEST")"

echo
echo "Claude Code 안에서 아래를 직접 실행해야 한다:"
echo
echo "  /plugin marketplace add $REPO"
# 플러그인이 여럿이다. 마켓플레이스에 있는 것을 전부 낸다.
python3 -c 'import json,sys
for p in json.load(open(sys.argv[1]))["plugins"]:
    print("  /plugin install %s@%s" % (p["name"], sys.argv[2]))' "$MANIFEST" "$MARKET"
