#!/usr/bin/env bash
# 새 머신이나 컨테이너에서 서드파티 마켓플레이스·플러그인을 복원한다.
# ~/.claude/settings.json 의 extraKnownMarketplaces 와 enabledPlugins 에 기록만 하고,
# 실제 내려받기는 Claude Code 가 다음 기동 때 수행한다.
#
# 이 스크립트가 존재하는 이유: 서드파티 플러그인은 각자의 마켓플레이스에 그대로
# 두어 업데이트를 계속 받게 하되(요구사항 0-4), 새 환경 복원은 한 번에 끝내기
# 위해서다. 이 저장소는 서드파티 코드를 복사하거나 fork 하지 않는다.
set -euo pipefail

SETTINGS="${CLAUDE_HOME:-$HOME/.claude}/settings.json"
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

python3 - "$SETTINGS" <<'PY'
import json, sys, datetime, shutil, os

path = sys.argv[1]

MARKETPLACES = {
    "karpathy-skills": {"source": "github", "repo": "forrestchang/andrej-karpathy-skills"},
    "im-not-ai":       {"source": "github", "repo": "epoko77-ai/im-not-ai"},
}
# claude-plugins-official 은 Claude Code 에 기본 내장되어 있어 등록이 필요 없다.
PLUGINS = [
    "andrej-karpathy-skills@karpathy-skills",
    "frontend-design@claude-plugins-official",
    "humanize-korean@im-not-ai",
]

with open(path, encoding="utf-8") as f:
    try:
        cfg = json.load(f)
    except json.JSONDecodeError as e:
        sys.exit(f"오류: {path} 파싱 실패 — {e}")

bak = f"{path}.bak.{datetime.datetime.now():%Y%m%d%H%M%S}"
shutil.copy2(path, bak)

changed = []
markets = cfg.setdefault("extraKnownMarketplaces", {})
for name, src in MARKETPLACES.items():
    if markets.get(name, {}).get("source") != src:
        markets[name] = {"source": src}
        changed.append(f"마켓플레이스 추가: {name} ({src['repo']})")

enabled = cfg.setdefault("enabledPlugins", {})
for p in PLUGINS:
    if enabled.get(p) is not True:
        enabled[p] = True
        changed.append(f"플러그인 활성화: {p}")

if changed:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"백업: {bak}")
    for c in changed:
        print("  " + c)
    print("\nClaude Code 를 재시작하면 내려받기가 시작된다.")
else:
    os.remove(bak)
    print("변경 없음 — 서드파티 플러그인이 이미 전부 등록돼 있다.")
PY
