#!/usr/bin/env bash
# 추적 사슬 검사. 인자로 문서 디렉터리를 받는다 (기본값: docs).
#
#   사슬 A: charter.md 6 성공 기준 (SC-nn) -> journal.md 15 검증 -> report.md 17 판정
#   사슬 B: charter.md 7 기능 요구사항 (FR-nn) -> design.md 12 구현 -> journal.md 15 검증
#   ADR:   본문이 참조하는 ADR-nnnn 에 decisions/nnnn-*.md 가 있는가
#   진척:  몇 개 중 몇 개가 채워졌는가 (재개할 때 읽는 요약)
#
# ID 를 찾을 때 파일 전체가 아니라 해당 절만 본다. 절을 나누지 않으면 14 작업 로그나
# 16 변경 이력의 언급이 검증 기록으로 집계된다.
#
# 종료 코드는 무엇이 걸렸는지를 구분한다. 자동 판단에 쓴다.
#
#   0  끊긴 사슬도 승급 신호도 없다
#   1  사슬이 끊겼다 (ADR 참조 파손 포함)
#   2  프로파일 승급 신호가 떴다
#   3  둘 다
#   9  실행 오류 (디렉터리나 charter.md 가 없다)
#
# 없는 파일은 건너뛴다. 진행 중인 M 프로젝트에는 report.md 가 없다.
set -uo pipefail

DOCS="${1:-docs}"
DOCS="${DOCS%/}"   # 끝의 / 를 떼야 출력 경로에 // 가 안 생긴다
[ -d "$DOCS" ] || { echo "오류: $DOCS 가 없다." >&2; exit 9; }

CHARTER="$DOCS/charter.md"
DESIGN="$DOCS/design.md"
JOURNAL="$DOCS/journal.md"
# 월별 보관으로 옮긴 지난 달 로그도 검증 참조 대상이다.
ARCHIVES=("$DOCS"/journal/*.md)
REPORT="$DOCS/report.md"

[ -f "$CHARTER" ] || { echo "오류: $CHARTER 가 없다." >&2; exit 9; }

# 파일에서 '## N.' 절 하나만 잘라낸다.
section() {  # section <파일> <항목번호>
  [ -f "$1" ] || return 0
  awk -v n="$2" '$0 ~ "^## *" n "\\." {f=1;next} /^## /{f=0} f' "$1"
}

# 15 검증 기록. journal.md 와 월별 보관 파일을 합쳐서 본다.
section15() {
  section "$JOURNAL" 15
  for f in "${ARCHIVES[@]}"; do section "$f" 15; done
}

pick() { grep -oE "$1" | sort -u | grep -v '^$' || true; }
only() { comm -23 <(printf '%s\n' "$1" | grep -v '^$') <(printf '%s\n' "$2" | grep -v '^$'); }
extra() { comm -13 <(printf '%s\n' "$1" | grep -v '^$') <(printf '%s\n' "$2" | grep -v '^$'); }
inter() { comm -12 <(printf '%s\n' "$1" | grep -v '^$') <(printf '%s\n' "$2" | grep -v '^$'); }

# 표에서 ID 열과 값 열을 탭으로 묶어 낸다. 열을 찾는 방식은 cell_blank 과 같다.
cell_pairs() {  # cell_pairs <값 열 이름> <ID 열 이름>   (표준입력)
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
        v  = $vcol; gsub(/^[ \t]+|[ \t]+$/, "", v);  gsub(/[`*]/, "", v)
        id = $icol; gsub(/^[ \t]+|[ \t]+$/, "", id); gsub(/[`*]/, "", id)
        if (id ~ /[0-9]/) print id "\t" v
      }
      prev = $0
    }'
}

# charter 에서 정의된 ID. 표 첫 열에 있는 것만 정의로 본다.
def_sc=$(grep -oE '^\| *(SC-[0-9]+)' "$CHARTER" | pick 'SC-[0-9]+')
def_fr=$(grep -oE '^\| *(FR-[0-9]+)' "$CHARTER" | pick 'FR-[0-9]+')

# FR 패턴에는 반드시 \b 를 붙인다. 'NFR-03' 안에 'FR-03' 이 문자열로 들어 있어서,
# \b 가 없으면 비기능 요구사항 언급이 기능 요구사항 구현으로 집계된다.
use_j_sc=$(section15 | pick 'SC-[0-9]+')
use_j_fr=$(section15 | pick '\bFR-[0-9]+')
use_design=$(section "$DESIGN" 12 | pick '\bFR-[0-9]+')
# 12 에서 상태가 미착수인 요구사항. 표에 줄이 있다고 구현된 것은 아니다.
todo_fr=$(section "$DESIGN" 12 | cell_pairs 상태 FR \
          | awk -F'\t' '$2 ~ /미착수/ {print $1}' | grep -oE '\bFR-[0-9]+' | sort -u || true)
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

# 15 의 방법 칸이 약한 근거뿐인데 17 에서 달성으로 판정된 성공 기준.
# 에이전트가 쓴 테스트를 에이전트가 통과시킨 것(테스트(미확인))과 LLM 검토는 판정 근거가
# 아니다. 라벨 자체가 자기 신고라, 거짓 라벨은 이 검사로 잡지 못한다.
weak_evidence() {
  local ver_pairs weak rid verdict sc
  ver_pairs=$(section15 | cell_pairs 방법 대상)
  if [ -z "$ver_pairs" ]; then
    echo "  참고: journal.md 15 에 방법 칸이 없다. 판정 근거의 강도는 검사하지 못한다."
    return 0
  fi
  weak=""
  while IFS="$(printf '\t')" read -r rid verdict; do
    [ "$verdict" = "달성" ] || continue
    sc=$(printf '%s' "$rid" | grep -oE 'SC-[0-9]+' | head -1)
    [ -n "$sc" ] || continue
    printf '%s\n' "$ver_pairs" | awk -F'\t' -v sc="$sc" '
      index($1, sc) && ($2 == "타입·컴파일" || $2 == "테스트(스펙 확인)" \
        || $2 == "실행" || $2 == "정적분석") { found = 1 }
      END { exit !found }' || weak="${weak}${sc}"$'\n'
  done < <(section "$REPORT" 17 | cell_pairs 판정 ID)
  report "약한 근거만으로 달성 판정된 성공 기준 (15 방법 칸):" \
    "$(printf '%s' "$weak" | sort -u | grep -v '^$')"
}

chain=0      # 사슬 파손
promote=0    # 승급 신호
report() {  # report <제목> <목록>
  [ -n "$2" ] || return 0
  chain=1
  echo "  $1"
  echo "$2" | sed 's/^/    - /'
}

echo "== 사슬 A: 성공 기준 -> 검증 -> 판정 =="
if [ -z "$def_sc" ]; then
  echo "  경고: charter.md 에 SC ID 가 하나도 없다. 성공 기준이 판정 불가 문장일 수 있다."
  chain=1
else
  report "검증 기록이 없는 성공 기준 (journal.md 15):" "$(only "$def_sc" "$use_j_sc")"
  report "실측값이 비어 있는 검증 행 (journal.md 15):" \
    "$(section15 | cell_blank 실측값 대상)"
  if [ -f "$REPORT" ]; then
    report "판정이 없는 성공 기준 (report.md 17):" "$(only "$def_sc" "$use_report")"
    report "판정이 확정되지 않은 성공 기준 (report.md 17):" \
      "$(section "$REPORT" 17 | cell_blank 판정 ID)"
    weak_evidence
  fi
fi

echo "== 사슬 B: 요구사항 -> 구현 -> 검증 =="
if [ -z "$def_fr" ]; then
  echo "  경고: charter.md 에 FR ID 가 하나도 없다."
  chain=1
else
  if [ -f "$DESIGN" ]; then
    report "구현 기록이 없는 요구사항 (design.md 12):" "$(only "$def_fr" "$use_design")"
    report "charter 에 없는데 design 이 참조하는 FR:" "$(extra "$def_fr" "$use_design")"
    report "구현 상태가 확정되지 않은 요구사항 (design.md 12):" \
      "$(section "$DESIGN" 12 | cell_blank 상태 FR)"
  fi
  report "검증 기록이 없는 요구사항 (journal.md 15):" "$(only "$def_fr" "$use_j_fr")"
fi

echo "== ADR 참조 =="
# decisions/ 에 있는 결정. 파일 이름 앞 네 자리가 번호다.
have_adr=""
for f in "$DOCS"/decisions/*.md; do
  [ -f "$f" ] || continue
  b=$(basename "$f")
  case "$b" in
    [0-9][0-9][0-9][0-9]-*) have_adr="${have_adr}ADR-${b%%-*}"$'\n' ;;
  esac
done
have_adr=$(printf '%s' "$have_adr" | sort -u | grep -v '^$' || true)
# 본문이 참조하는 결정. 템플릿의 ADR-NNNN 은 숫자가 아니라 걸리지 않는다.
used_adr=$(grep -rhoE 'ADR-[0-9]{4}' "$DOCS" 2>/dev/null | sort -u | grep -v '^$' || true)
report "참조된 ADR 에 해당 파일이 없다 (decisions/):" "$(only "$used_adr" "$have_adr")"
[ -n "$have_adr" ] || echo "  결정 기록 없음."
# 아무도 참조하지 않는 ADR 은 잡지 않는다. 단독으로 서는 결정이 정상이다.

# 목록의 줄 수. 빈 문자열이면 0 이다.
n() { printf '%s\n' "$1" | grep -vc '^$'; }

echo "== 진척 =="
# 세는 기준은 "ID 가 적혀 있다"가 아니라 "칸까지 채워졌다"다. 언급만 있고 실측값이나
# 판정이 빈 행은 위에서 이미 끊긴 것으로 잡혔으므로 여기서도 빼야 숫자가 맞는다.
done_n() {  # done_n <정의 목록> <참조 목록> <미확정 ID 목록>
  n "$(only "$(inter "$1" "$2")" "$3")"
}
t_sc=$(n "$def_sc"); t_fr=$(n "$def_fr")
v_sc=$(done_n "$def_sc" "$use_j_sc" "$(section15 | cell_blank 실측값 대상)")
i_fr=$(done_n "$def_fr" "$use_design" "$(printf '%s\n%s' \
        "$(section "$DESIGN" 12 | cell_blank 상태 FR)" "$todo_fr")")
w_fr=$(done_n "$def_fr" "$use_j_fr" "$(section15 | cell_blank 실측값 대상)")
if [ -f "$REPORT" ]; then
  d_sc="$(done_n "$def_sc" "$use_report" "$(section "$REPORT" 17 | cell_blank 판정 ID)")개 판정"
else
  d_sc="판정 없음 (report.md 없음)"
fi
echo "  성공 기준 ${t_sc}개 중 ${v_sc}개 검증 · ${d_sc}"
echo "  요구사항 ${t_fr}개 중 ${i_fr}개 구현 · ${w_fr}개 검증"
if [ -n "$todo_fr" ]; then
  echo "  미착수 $(n "$todo_fr")개 — 착수 순서는 design.md 12 에 있다: $(printf '%s' "$todo_fr" | tr '\n' ' ')"
fi

# 미결 결정. 되돌릴 수 없는데 아직 답이 없는 것이라, 그 영역은 건드리기 전에 정해야 한다.
open_adr=$(grep -lE '^\| *상태 *\|[^|]*미결' "$DOCS"/decisions/*.md 2>/dev/null || true)
if [ -n "$open_adr" ]; then
  echo "  미결 결정 $(n "$open_adr")건 — 이 영역을 건드리기 전에 답을 정한다:"
  echo "$open_adr" | sed 's#^#    - #'
fi

last=$( { [ -f "$JOURNAL" ] && cat "$JOURNAL"; } 2>/dev/null \
        | grep -oE '^### [0-9]{4}-[0-9]{2}-[0-9]{2}' | grep -oE '[0-9-]{10}' | sort | tail -1)
[ -n "$last" ] && echo "  마지막 작업 기록: $last"

# 프로파일은 charter 헤더의 '프로파일' 행에서 읽는다. 파일 존재로 판정하면 M 프로젝트가
# 종료하면서 report.md 를 만든 순간 L 로 잘못 읽힌다. 헤더에 M 도 L 도 없으면 템플릿
# 플레이스홀더가 남은 것이므로 그것 자체를 잡는다.
profile() {
  grep -oE '^\| *프로파일 *\| *[ML] *\|' "$CHARTER" | grep -oE '[ML]' | head -1
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
if [ -z "$prof" ]; then
  echo "  경고: charter.md 헤더의 프로파일이 M 도 L 도 아니다. 템플릿 잔재를 지운다."
  chain=1
fi
start=$(first_date)
days=""
if [ -n "$start" ]; then
  s_epoch=$(date -d "$start" +%s 2>/dev/null) && days=$(( ( $(date +%s) - s_epoch ) / 86400 ))
fi
files=$(tracked_count) || files=""

echo "  현재: ${prof:-미상} (charter 헤더 기준)${start:+ · 시작 $start${days:+, ${days}일 경과}}${files:+ · 추적 파일 ${files}개}"

signals=""
case "$prof" in
  M)
    [ -n "$days" ] && [ "$days" -ge 30 ] && signals="${signals}    - ${days}일 걸렸다 (기준 한 달 초과)"$'\n'
    next=L ;;
  *) next="" ;;
esac

if [ -n "$signals" ]; then
  promote=1
  echo "  $next 승급 조건에 걸렸다:"
  printf '%s' "$signals"
  echo "    (기계가 못 재는 신호: 결정을 뒤집었나 / 남이 손대나 / 배포 대상이 있나)"
elif [ -n "$next" ]; then
  echo "  $next 승급 신호 없음."
fi

echo
if [ "$chain" -eq 0 ] && [ "$promote" -eq 0 ]; then
  echo "끊긴 사슬 없음."
else
  echo "위 항목을 채우거나 승급하고, 하지 않는다면 그 이유를 보고에 적는다."
fi
exit $(( chain + promote * 2 ))
