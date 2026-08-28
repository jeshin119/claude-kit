#!/usr/bin/env bash
# 추적 사슬 검사. 인자로 문서 디렉터리를 받는다 (기본값: docs).
#
#   사슬 A: charter.md 5 성공 기준 (SC-nn) -> journal.md 14 검증 -> report.md 16 판정
#   사슬 B: charter.md 6 기능 요구사항 (FR-nn) -> design.md 11 구현 -> journal.md 14 검증
#
# 끊긴 곳을 출력하고, 하나라도 있으면 1로 끝난다.
# 없는 파일은 건너뛴다. 프로파일 S 에는 design.md 와 report.md 가 없다.
set -uo pipefail

DOCS="${1:-docs}"
[ -d "$DOCS" ] || { echo "오류: $DOCS 가 없다." >&2; exit 2; }

CHARTER="$DOCS/charter.md"
DESIGN="$DOCS/design.md"
JOURNAL="$DOCS/journal.md"
# 롤오버된 지난 달 로그도 검증 참조 대상이다.
ARCHIVES=("$DOCS"/journal/*.md)
REPORT="$DOCS/report.md"

[ -f "$CHARTER" ] || { echo "오류: $CHARTER 가 없다." >&2; exit 2; }

ids() { [ -f "$1" ] && grep -oE "$2" "$1" | sort -u | grep -v '^$' || true; }
# journal.md 와 롤오버 아카이브를 합쳐서 본다.
journal_ids() {
  { [ -f "$JOURNAL" ] && cat "$JOURNAL"; for f in "${ARCHIVES[@]}"; do [ -f "$f" ] && cat "$f"; done; } 2>/dev/null \
    | grep -oE "$1" | sort -u | grep -v '^$' || true
}
only() { comm -23 <(printf '%s\n' "$1" | grep -v '^$') <(printf '%s\n' "$2" | grep -v '^$'); }
extra() { comm -13 <(printf '%s\n' "$1" | grep -v '^$') <(printf '%s\n' "$2" | grep -v '^$'); }

# charter 에서 정의된 ID. 표 첫 열에 있는 것만 정의로 본다.
def_sc=$(grep -oE '^\| *(SC-[0-9]+)' "$CHARTER" | grep -oE 'SC-[0-9]+' | sort -u)
def_fr=$(grep -oE '^\| *(FR-[0-9]+)' "$CHARTER" | grep -oE 'FR-[0-9]+' | sort -u)

use_journal=$(journal_ids 'SC-[0-9]+|FR-[0-9]+')
use_design=$(ids "$DESIGN" 'FR-[0-9]+')
use_report=$(ids "$REPORT" 'SC-[0-9]+')

fail=0
report() {  # report <제목> <목록>
  [ -n "$2" ] || return 0
  fail=1
  echo "  $1"
  echo "$2" | sed 's/^/    - /'
}

echo "== 사슬 A: 성공 기준 -> 검증 -> 판정 =="
if [ -z "$def_sc" ]; then
  echo "  경고: charter.md 에 SC ID 가 하나도 없다. 성공 기준이 판정 불가 문장일 수 있다."
  fail=1
else
  report "검증 기록이 없는 성공 기준 (journal.md 14):" \
    "$(only "$def_sc" "$(printf '%s\n' "$use_journal" | grep -oE 'SC-[0-9]+' | sort -u)")"
  if [ -f "$REPORT" ]; then
    report "판정이 없는 성공 기준 (report.md 16):" \
      "$(only "$def_sc" "$use_report")"
  fi
fi

echo "== 사슬 B: 요구사항 -> 구현 -> 검증 =="
if [ -z "$def_fr" ]; then
  echo "  경고: charter.md 에 FR ID 가 하나도 없다."
  fail=1
else
  if [ -f "$DESIGN" ]; then
    report "구현 기록이 없는 요구사항 (design.md 11):" \
      "$(only "$def_fr" "$use_design")"
    report "charter 에 없는데 design 이 참조하는 FR:" \
      "$(extra "$def_fr" "$use_design")"
  fi
  report "검증 기록이 없는 요구사항 (journal.md 14):" \
    "$(only "$def_fr" "$(printf '%s\n' "$use_journal" | grep -oE 'FR-[0-9]+' | sort -u)")"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "끊긴 사슬 없음."
else
  echo "위 항목을 채우거나, 채우지 않는 이유를 보고에 적는다."
fi
exit "$fail"
