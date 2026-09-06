#!/usr/bin/env bash
# 이 저장소의 파일을 홈 아래 제자리로 심링크한다.
#
#   shared/CLAUDE.md -> ~/.claude/CLAUDE.md
#   bin/csess        -> ~/.local/bin/csess
#
# 두 번 실행해도 같은 결과가 되도록 만들었다.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}"
BIN_DIR="${CLAUDE_KIT_BIN:-$HOME/.local/bin}"

link_one() {
  local src="$1" dst="$2"

  [ -e "$src" ] || { echo "오류: $src 가 없다." >&2; exit 1; }
  mkdir -p "$(dirname "$dst")"

  if [ -L "$dst" ]; then
    local cur
    cur="$(readlink -f "$dst" || true)"
    if [ "$cur" = "$(readlink -f "$src")" ]; then
      echo "이미 올바른 심링크다: $dst -> $src"
    else
      echo "다른 대상을 가리키는 심링크를 교체한다: $cur"
      ln -sfn "$src" "$dst"
      echo "심링크 생성: $dst -> $src"
    fi
  elif [ -e "$dst" ]; then
    local bak="$dst.bak.$(date +%Y%m%d%H%M%S)"
    mv "$dst" "$bak"
    echo "기존 실제 파일을 백업했다: $bak"
    ln -s "$src" "$dst"
    echo "심링크 생성: $dst -> $src"
  else
    ln -s "$src" "$dst"
    echo "심링크 생성: $dst -> $src"
  fi
}

link_one "$REPO/shared/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
link_one "$REPO/bin/csess" "$BIN_DIR/csess"

# csess 는 PATH 에 있어야 이름만으로 불린다. 없으면 알려만 주고 셸 설정은 건드리지 않는다.
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo
    echo "$BIN_DIR 이 PATH 에 없다. 셸 설정에 아래를 넣어야 csess 가 불린다:"
    echo "  export PATH=\"$BIN_DIR:\$PATH\""
    ;;
esac

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
