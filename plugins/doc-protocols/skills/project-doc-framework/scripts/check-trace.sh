#!/usr/bin/env bash
# 추적 사슬 검사. 인자로 문서 디렉터리를 받는다 (기본값: docs).
#
#   사슬 A: charter.md 6 성공 기준 (SC-nn) -> journal.md 15 검증 -> report.md 17 판정
#   사슬 B: charter.md 7 기능 요구사항 (FR-nn) -> design.md 12 구현 -> journal.md 15 검증
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

# FR 패턴에는 반드시 \b 를 붙인다. 'NFR-03' 안에 'FR-03' 이 문자열로 들어 있어서,
# \b 가 없으면 비기능 요구사항 언급이 기능 요구사항 구현으로 집계된다.
use_journal=$(journal_ids 'SC-[0-9]+|\bFR-[0-9]+')
use_design=$(ids "$DESIGN" '\bFR-[0-9]+')
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
  report "검증 기록이 없는 성공 기준 (journal.md 15):" \
    "$(only "$def_sc" "$(printf '%s\n' "$use_journal" | grep -oE 'SC-[0-9]+' | sort -u)")"
  if [ -f "$REPORT" ]; then
    report "판정이 없는 성공 기준 (report.md 17):" \
      "$(only "$def_sc" "$use_report")"
  fi
fi

echo "== 사슬 B: 요구사항 -> 구현 -> 검증 =="
if [ -z "$def_fr" ]; then
  echo "  경고: charter.md 에 FR ID 가 하나도 없다."
  fail=1
else
  if [ -f "$DESIGN" ]; then
    report "구현 기록이 없는 요구사항 (design.md 12):" \
      "$(only "$def_fr" "$use_design")"
    report "charter 에 없는데 design 이 참조하는 FR:" \
      "$(extra "$def_fr" "$use_design")"
  fi
  report "검증 기록이 없는 요구사항 (journal.md 15):" \
    "$(only "$def_fr" "$(printf '%s\n' "$use_journal" | grep -oE '\bFR-[0-9]+' | sort -u)")"
fi

# 프로파일은 파일 존재로 판정한다. charter 헤더를 파싱하지 않는 이유는
# 템플릿 플레이스홀더("S / M / L")가 안 채워진 채로 남아도 알 수 없기 때문이다.
profile() {
  [ -f "$DESIGN" ] || { echo S; return; }
  [ -f "$REPORT" ] || { echo M; return; }
  echo L
}

# 문서에 적힌 날짜 중 가장 오래된 것. 템플릿 플레이스홀더는 안 잡힌다.
first_date() {
  { [ -f "$CHARTER" ] && cat "$CHARTER"
    [ -f "$JOURNAL" ] && cat "$JOURNAL"
    for f in "${ARCHIVES[@]}"; do [ -f "$f" ] && cat "$f"; done
  } 2>/dev/null | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort | head -1
}

# git 추적 파일 수. 문서 디렉터리는 뺀다. 문서가 스스로 승급 신호를 만들면 안 된다.
tracked_count() {
  local root docs_abs prefix
  root=$(git -C "$DOCS" rev-parse --show-toplevel 2>/dev/null) || return 1
  docs_abs=$(cd "$DOCS" && pwd) || return 1
  if [ "$docs_abs" = "$root" ]; then
    git -C "$root" ls-files | grep -c ''
  else
    prefix=${docs_abs#"$root"/}
    git -C "$root" ls-files | grep -vc "^${prefix}/"
  fi
}

echo "== 프로파일 승급 =="
prof=$(profile)
start=$(first_date)
days=""
if [ -n "$start" ]; then
  s_epoch=$(date -d "$start" +%s 2>/dev/null) && days=$(( ( $(date +%s) - s_epoch ) / 86400 ))
fi
files=$(tracked_count) || files=""

echo "  현재: $prof (문서 파일 기준)${start:+ · 시작 $start${days:+, ${days}일 경과}}${files:+ · 추적 파일 ${files}개}"

signals=""
case "$prof" in
  S)
    [ -n "$files" ] && [ "$files" -gt 5 ] && signals="${signals}    - 추적 파일이 ${files}개다 (기준 5개 초과)"$'\n'
    [ -n "$days" ] && [ "$days" -ge 2 ] && signals="${signals}    - ${days}일 걸렸다 (기준 이틀 이상)"$'\n'
    [ -d "$DOCS/decisions" ] && signals="${signals}    - decisions/ 가 이미 있다"$'\n'
    next=M ;;
  M)
    [ -n "$days" ] && [ "$days" -ge 30 ] && signals="${signals}    - ${days}일 걸렸다 (기준 한 달 초과)"$'\n'
    next=L ;;
  *) next="" ;;
esac

if [ -n "$signals" ]; then
  fail=1
  echo "  $next 승급 조건에 걸렸다:"
  printf '%s' "$signals"
  echo "    (기계가 못 재는 신호: 결정을 뒤집었나 / 남이 손대나 / 배포 대상이 있나)"
elif [ -n "$next" ]; then
  echo "  $next 승급 신호 없음."
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "끊긴 사슬 없음."
else
  echo "위 항목을 채우거나 승급하고, 하지 않는다면 그 이유를 보고에 적는다."
fi
exit "$fail"
