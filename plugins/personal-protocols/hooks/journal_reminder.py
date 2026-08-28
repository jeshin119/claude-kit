#!/usr/bin/env python3
"""Stop 훅. 오늘 코드를 고쳤는데 journal.md 에 오늘 날짜가 없으면 한 번만 알린다.

발동 조건을 좁게 잡은 이유: Stop 훅이 자주 걸리면 무시하게 되고, 무시하기
시작하면 없는 것과 같다. 아래 넷을 전부 만족할 때만 발동한다.

  1. 재발동이 아니다 (stop_hook_active 가 false)
  2. <docs>/journal.md 가 존재한다  -- 문서를 쓰기로 한 프로젝트만 해당
  3. journal.md 에 오늘 날짜(YYYY-MM-DD)가 없다
  4. git 이 추적하는 파일 중 오늘 수정된 것이 있다  -- 실제로 일한 날만 해당

조건이 안 맞으면 아무것도 출력하지 않고 0 으로 끝난다.
"""
import json
import os
import subprocess
import sys
from datetime import date, datetime

DOC_DIRS = ("docs", "doc", ".")


def today_str():
    return date.today().isoformat()


def find_journal(cwd):
    for d in DOC_DIRS:
        p = os.path.join(cwd, d, "journal.md")
        if os.path.isfile(p):
            return p
    return None


def edited_today(cwd):
    """git 추적 파일 중 오늘 mtime 인 것이 있는가."""
    try:
        out = subprocess.run(
            ["git", "-C", cwd, "ls-files"],
            capture_output=True, text=True, timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    if out.returncode != 0:
        return False
    start = datetime.combine(date.today(), datetime.min.time()).timestamp()
    for rel in out.stdout.splitlines():
        full = os.path.join(cwd, rel)
        try:
            if os.path.getmtime(full) >= start:
                return True
        except OSError:
            continue
    return False


def main():
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0

    if payload.get("stop_hook_active"):
        return 0

    cwd = payload.get("cwd") or os.getcwd()
    journal = find_journal(cwd)
    if not journal:
        return 0

    try:
        with open(journal, encoding="utf-8") as f:
            body = f.read()
    except OSError:
        return 0

    if today_str() in body:
        return 0
    if not edited_today(cwd):
        return 0

    rel = os.path.relpath(journal, cwd)
    print(json.dumps({
        "decision": "block",
        "reason": (
            f"오늘 코드를 고쳤는데 {rel} 에 {today_str()} 기록이 없다. "
            "`/doc-log` 절차대로 13 작업 로그와 14 검증 기록을 붙이고, "
            "붙일 내용이 없다고 판단되면 그 이유를 한 줄로 말하고 멈춰라. "
            "이 알림은 세션당 한 번만 뜬다."
        ),
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
