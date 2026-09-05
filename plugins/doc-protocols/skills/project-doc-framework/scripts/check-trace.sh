#!/usr/bin/env bash
# 추적 사슬 검사. 인자로 문서 디렉터리를 받는다 (기본값: docs).
#
#   사슬 A: charter.md 6 성공 기준 (SC-nn) -> journal.md 15 검증 -> report.md 17 판정
#   사슬 B: charter.md 7 기능 요구사항 (FR-nn) -> design.md 12 구현 -> journal.md 15 검증
#
# ID 를 찾을 때 파일 전체가 아니라 해당 절만 본다. 절을 나누지 않으면 14 작업 로그나
# 16 변경 이력의 언급이 검증 기록으로 집계된다.
#
# 끊긴 곳을 출력하고, 하나라도 있으면 1 로 끝난다.
# 없는 파일은 건너뛴다. 프로파일 M 에는 report.md 가 없다.
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

# 파일에서 '## N.' 절 하나만 잘라낸다.
section() {  # section <파일> <항목번호>
  [ -f "$1" ] || return 0
  awk -v n="$2" '$0 ~ "^## *" n "\\." {f=1;next} /^## /{f=0} f' "$1"
}

# 15 검증 기록. journal.md 와 롤오버 아카이브를 합쳐서 본다.
section15() {
  section "$JOURNAL" 15
  for f in "${ARCHIVES[@]}"; do section "$f" 15; done
}

pick() { grep -oE "$1" | sort -u | grep -v '^$' || true; }
only() { comm -23 <(printf '%s\n' "$1" | grep -v '^$') <(printf '%s\n' "$2" | grep -v '^$'); }
extra() { comm -13 <(printf '%s\n' "$1" | grep -v '^$') <(printf '%s\n' "$2" | grep -v '^$'); }

# charter 에서 정의된 ID. 표 첫 열에 있는 것만 정의로 본다.
def_sc=$(grep -oE '^\| *(SC-[0-9]+)' "$CHARTER" | pick 'SC-[0-9]+')
def_fr=$(grep -oE '^\| *(FR-[0-9]+)' "$CHARTER" | pick 'FR-[0-9]+')

# FR 패턴에는 반드시 \b 를 붙인다. 'NFR-03' 안에 'FR-03' 이 문자열로 들어 있어서,
# \b 가 없으면 비기능 요구사항 언급이 기능 요구사항 구현으로 집계된다.
use_j_sc=$(section15 | pick 'SC-[0-9]+')
use_j_fr=$(section15 | pick '\bFR-[0-9]+')
use_design=$(section "$DESIGN" 12 | pick '\bFR-[0-9]+')
use_report=$(section "$REPORT" 17 | pick 'SC-[0-9]+')

# 표의 한 칸이 채워졌는지 본다. 열 위치는 헤더 행에서 이름으로 찾으므로 열 순서가
# 바뀌어도 따라가고, 구분선을 만날 때마다 다시 잡으므로 한 절에 표가 여럿이어도 된다.
# 그 이름의 열이 없는 표는 통째로 건너뛴다.
cell_blank() {  # cell_blank <값 열 이름> <ID 열 이름>   (표준입력)
  awk -F'|' -v want="$1" -v idname="$2" '
    /^\|[ :|-]*-[ :|-]*$/ {
      vcol = 0; icol = 0
      n = split(prev, h, "|")
      for (i = 2; i <= n; i++) {
        t = h[i]; gsub(/^[ \t]+|[ \t]+$/, "", t)
        if (t == want)   vcol = i
        if (t == idname) icol = i
      }
      prev = $0; next
    }
    {
      if (vcol > 0 && icol > 0 && $0 ~ /^\|/) {
        v  = $vcol; gsub(/^[ \t]+|[ \t]+$/, "", v); gsub(/[`*]/, "", v)
        id = $icol; gsub(/^[ \t]+|[ \t]+$/, "", id)
        # 헤더 행은 자기 구분선보다 먼저 읽히므로 ID 열에 숫자가 있는 행만 데이터로 본다.
        if (id ~ /[0-9]/ && (v == "" \
            || v ~ /^(달성 *\/ *미달|완료 *\/ *진행( *\/ *미착수)?|진행 *\/ *보류( *\/ *종료)?)$/ \
            || v ~ /미판정|미측정|미정|보류/)) print id
      }
      prev = $0
    }' | sort -u
}

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
  report "검증 기록이 없는 성공 기준 (journal.md 15):" "$(only "$def_sc" "$use_j_sc")"
  report "실측값이 비어 있는 검증 행 (journal.md 15):" \
    "$(section15 | cell_blank 실측값 대상)"
  if [ -f "$REPORT" ]; then
    report "판정이 없는 성공 기준 (report.md 17):" "$(only "$def_sc" "$use_report")"
    report "판정이 확정되지 않은 성공 기준 (report.md 17):" \
      "$(section "$REPORT" 17 | cell_blank 판정 ID)"
  fi
fi

echo "== 사슬 B: 요구사항 -> 구현 -> 검증 =="
if [ -z "$def_fr" ]; then
  echo "  경고: charter.md 에 FR ID 가 하나도 없다."
  fail=1
else
  if [ -f "$DESIGN" ]; then
    report "구현 기록이 없는 요구사항 (design.md 12):" "$(only "$def_fr" "$use_design")"
    report "charter 에 없는데 design 이 참조하는 FR:" "$(extra "$def_fr" "$use_design")"
    report "구현 상태가 확정되지 않은 요구사항 (design.md 12):" \
      "$(section "$DESIGN" 12 | cell_blank 상태 FR)"
  fi
  report "검증 기록이 없는 요구사항 (journal.md 15):" "$(only "$def_fr" "$use_j_fr")"
fi

# 프로파일은 파일 존재로 판정한다. charter 헤더를 파싱하지 않는 이유는
# 템플릿 플레이스홀더("M / L")가 안 채워진 채로 남아도 알 수 없기 때문이다.
profile() {
  [ -f "$REPORT" ] || { echo M; return; }
  echo L
}

# 시작일. charter 헤더의 '시작' 행이 첫 근거고, 없으면 git 첫 커밋을 쓴다.
# 본문 전체에서 가장 이른 날짜를 고르면 스펙 버전이나 인용 날짜를 시작일로 읽는다.
first_date() {
  local d
  d=$(grep -oE '^\| *시작 *\| *[0-9]{4}-[0-9]{2}-[0-9]{2}' "$CHARTER" 2>/dev/null \
      | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
  [ -n "$d" ] && { echo "$d"; return; }
  d=$(git -C "$DOCS" log --reverse --format=%ad --date=short 2>/dev/null | head -1)
  [ -n "$d" ] && { echo "$d"; return; }
  { [ -f "$JOURNAL" ] && cat "$JOURNAL"
    for f in "${ARCHIVES[@]}"; do [ -f "$f" ] && cat "$f"; done
  } 2>/dev/null | grep -oE '^### [0-9]{4}-[0-9]{2}-[0-9]{2}' \
    | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort | head -1
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
