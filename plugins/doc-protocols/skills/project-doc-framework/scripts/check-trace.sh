#!/usr/bin/env bash
# 추적 사슬 검사. 인자로 문서 디렉터리를 받는다 (기본값: docs).
#
#   사슬 A: charter.md 6 성공 기준 (SC-nn) -> journal.md 15 검증 -> report.md 17 판정
#   사슬 B: charter.md 7 기능 요구사항 (FR-nn) -> design.md 12 구현 -> journal.md 15 검증
#   ADR:   본문이 참조하는 ADR-nnnn 에 decisions/nnnn-*.md 가 있는가
#   진척:  몇 개 중 몇 개가 채워졌는가, 사람이 확인할 테스트가 남았는가 (재개할 때 읽는 요약)
#
# ID 를 찾을 때 해당 절만 보고 파일 전체는 보지 않는다. 절을 나누지 않으면 14 작업 로그나
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
[ -d "$DOCS" ] || { echo "오류: $DOCS가 없다." >&2; exit 9; }

CHARTER="$DOCS/charter.md"
DESIGN="$DOCS/design.md"
JOURNAL="$DOCS/journal.md"
# 월별 보관으로 옮긴 지난 달 로그도 검증 참조 대상이다.
ARCHIVES=("$DOCS"/journal/*.md)
REPORT="$DOCS/report.md"

[ -f "$CHARTER" ] || { echo "오류: $CHARTER가 없다." >&2; exit 9; }

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

# 15 검증 기록의 행마다 날짜, 대상, 방법, 확인 표시 유무(1 또는 0), 해시, 테스트 파일
# 이름을 탭으로 묶어 낸다. 확인 표시는 실측값 칸의
# '확인: <사람>, YYYY-MM-DD, 커밋 <해시 7자리 이상>, <테스트 파일 이름>'이고, 파일이
# 여럿이면 '·'로 잇는다. 빈 값은 '-'로 낸다. bash 의 read 는 탭이 연달아 오면 하나로
# 합쳐 칸이 밀리기 때문이다. 열을 찾는 방식은 cell_blank 과 같고, 반복 횟수 표기({7,})를
# 쓰지 않는 것은 mawk 에서도 돌게 하기 위해서다.
ver_rows() {  # (표준입력)
  awk -F'|' '
    /^\|[ :|-]*-[ :|-]*$/ {
      dcol = 0; icol = 0; mcol = 0; vcol = 0
      n = split(prev, h, "|")
      for (i = 2; i <= n; i++) {
        t = h[i]; gsub(/^[ \t]+|[ \t]+$/, "", t)
        if (t == "날짜")   dcol = i
        if (t == "대상")   icol = i
        if (t == "방법")   mcol = i
        if (t == "실측값") vcol = i
      }
      prev = $0; next
    }
    {
      if (icol > 0 && mcol > 0 && $0 ~ /^\|/) {
        d  = (dcol > 0) ? $dcol : ""; gsub(/^[ \t]+|[ \t]+$/, "", d)
        id = $icol; gsub(/^[ \t]+|[ \t]+$/, "", id); gsub(/[`*]/, "", id)
        m  = $mcol; gsub(/^[ \t]+|[ \t]+$/, "", m);  gsub(/[`*]/, "", m)
        v  = (vcol > 0) ? $vcol : ""; gsub(/[`*]/, "", v)
        s = 0; hash = ""; files = ""
        if (match(v, /확인: *[^,]+, *[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9], *커밋 *[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*/)) {
          s = 1
          stamp = substr(v, RSTART, RLENGTH)
          files = substr(v, RSTART + RLENGTH)
          if (match(stamp, /[0-9a-f]+$/)) hash = substr(stamp, RSTART, RLENGTH)
          sub(/^[ \t]*,[ \t]*/, "", files); sub(/[ \t.]+$/, "", files)
        }
        if (d == "") d = "-"
        if (hash == "") hash = "-"
        if (files == "") files = "-"
        if (id ~ /[0-9]/) print d "\t" id "\t" m "\t" s "\t" hash "\t" files
      }
      prev = $0
    }'
}

# ID 마다 가장 최근의 테스트 행(테스트(미확인) 또는 테스트(스펙 확인))을 낸다. 날짜로
# 정렬하고, 같은 날짜 안에서는 적힌 순서를 따른다. 확인한 뒤에 테스트(미확인) 행이 새로
# 붙으면 그 행이 가장 최근 행이 되므로, 한 번 확인한 ID 도 다시 확인 대기로 올라온다.
# 출력: ID, 방법, 확인 표시 유무, 해시, 테스트 파일 이름 (탭 구분, ID 순)
latest_tests() {  # (표준입력: ver_rows 출력)
  sort -s -t "$(printf '\t')" -k1,1 | awk -F'\t' '
    $3 == "테스트(미확인)" || $3 == "테스트(스펙 확인)" {
      rest = $2
      while (match(rest, /(SC|FR)-[0-9]+/)) {
        pre = (RSTART > 1) ? substr(rest, RSTART - 1, 1) : ""
        id = substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
        if (pre ~ /[A-Za-z]/) continue   # NFR-03 안의 FR-03 은 세지 않는다
        last[id] = $3 "\t" $4 "\t" $5 "\t" $6
      }
    }
    END { for (id in last) print id "\t" last[id] }' | sort
}

# 가장 최근 행에 확인 표시가 있는데 지금은 그 확인을 믿을 수 없는 ID 와 그 사유.
# 표시의 커밋이 저장소에 없거나, 표시의 테스트 파일을 찾지 못하거나 같은 이름이 여럿이라
# 특정할 수 없거나, 그 커밋 뒤에 파일이 바뀌었으면(커밋하지 않은 수정 포함) 다시 확인해야
# 한다. 문서와 테스트가 같은 git 저장소에 있다고 가정한다. 사유 문구는 파일 이름 뒤에
# 조사를 붙이지 않는다. 이름의 끝소리에 따라 조사가 달라지기 때문이다.
# 출력: ID, 사유 (탭 구분)
stale_tests() {  # (표준입력: latest_tests 출력)
  local id m s h files f p cnt why
  [ -n "$repo_root" ] || return 0
  while IFS="$(printf '\t')" read -r id m s h files; do
    [ "$m" = "테스트(스펙 확인)" ] && [ "$s" = 1 ] || continue
    if ! git -C "$repo_root" cat-file -e "${h}^{commit}" 2>/dev/null; then
      printf '%s\t%s\n' "$id" "저장소에 없는 커밋: $h"; continue
    fi
    if [ "$files" = "-" ]; then
      printf '%s\t%s\n' "$id" "확인 표시에 테스트 파일 이름이 없다"; continue
    fi
    why=""
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      case "$f" in
        */*) p=$(printf '%s\n' "$tracked" | awk -v n="$f" '$0 == n') ;;
        *)   p=$(printf '%s\n' "$tracked" | awk -F/ -v n="$f" '$NF == n') ;;
      esac
      cnt=$(printf '%s' "$p" | grep -c .)
      if [ "$cnt" -eq 0 ]; then
        why="${why}${why:+ / }찾지 못한 파일: $f"
      elif [ "$cnt" -gt 1 ]; then
        why="${why}${why:+ / }같은 이름이 ${cnt}개라 특정할 수 없는 파일: $f"
      elif ! git -C "$repo_root" diff --quiet "$h" -- "$p" 2>/dev/null; then
        why="${why}${why:+ / }커밋 $h 뒤에 바뀐 파일: $f"
      fi
    done < <(printf '%s\n' "$files" | awk -F' *· *' '{ for (i = 1; i <= NF; i++) print $i }')
    [ -z "$why" ] || printf '%s\t%s\n' "$id" "$why"
  done
}

# 15 의 방법 칸이 약한 근거뿐인데 17 에서 달성으로 판정된 성공 기준.
# 에이전트가 쓴 테스트를 에이전트가 통과시킨 것(테스트(미확인))과 LLM 검토는 판정 근거가
# 아니다. 테스트(스펙 확인)은 그 ID 의 가장 최근 테스트 행이 확인 표시를 갖고 있고 확인 뒤에
# 바뀌지 않았을 때만 센다. 확인 표시도 에이전트가 적는 값이라, 사람이 확인하지 않았는데
# 적은 표시는 이 검사로 검출하지 못한다.
weak_evidence() {
  local strong weak rid verdict sc
  if [ -z "$ver_all" ]; then
    echo "  참고: journal.md 15 검증 기록에 방법 칸이 없다. 판정 근거의 강도는 검사하지 못한다."
    return 0
  fi
  strong=$(printf '%s\n%s\n' \
    "$(printf '%s\n' "$ver_all" \
       | awk -F'\t' '$3 == "타입·컴파일" || $3 == "실행" || $3 == "정적분석" {print $2}' \
       | pick '\b(SC|FR)-[0-9]+')" \
    "$confirmed" | sort -u | grep -v '^$' || true)
  weak=""
  while IFS="$(printf '\t')" read -r rid verdict; do
    [ "$verdict" = "달성" ] || continue
    sc=$(printf '%s' "$rid" | grep -oE 'SC-[0-9]+' | head -1)
    [ -n "$sc" ] || continue
    printf '%s\n' "$strong" | grep -qx "$sc" || weak="${weak}${sc}"$'\n'
  done < <(section "$REPORT" 17 | cell_pairs 판정 ID)
  report "약한 근거만으로 달성 판정된 성공 기준 (15 검증 기록의 방법 칸):" \
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

# 15 검증 기록의 테스트 상태. 사슬 A 의 판정 근거 검사와 진척의 사람 확인 대기가 같이 쓴다.
ver_all=$(section15 | ver_rows)
repo_root=$(git -C "$DOCS" rev-parse --show-toplevel 2>/dev/null || true)
tracked=""
[ -z "$repo_root" ] || tracked=$(git -C "$repo_root" ls-files 2>/dev/null || true)
latest=$(printf '%s\n' "$ver_all" | grep -v '^$' | latest_tests)
stale=$(printf '%s\n' "$latest" | grep -v '^$' | stale_tests)
# 가장 최근 테스트 행에 확인 표시가 있고, 확인한 뒤에 바뀌지 않은 ID
confirmed=$(only \
  "$(printf '%s\n' "$latest" | awk -F'\t' '$2 == "테스트(스펙 확인)" && $3 == 1 {print $1}')" \
  "$(printf '%s\n' "$stale" | cut -f1 | sort -u)")
wait_ids=$(only "$(printf '%s\n' "$latest" | cut -f1)" "$confirmed")

echo "== 사슬 A: 성공 기준 -> 검증 -> 판정 =="
if [ -z "$def_sc" ]; then
  echo "  경고: charter.md에 SC ID가 하나도 없다. 성공 기준이 판정 불가 문장일 수 있다."
  chain=1
else
  report "검증 기록이 없는 성공 기준 (journal.md 15):" "$(only "$def_sc" "$use_j_sc")"
  report "실측값이 비어 있는 검증 행 (journal.md 15):" \
    "$(section15 | cell_blank 실측값 대상)"
  # 실측값이 빈 행과 같이 다룬다. 적어야 할 칸을 채우지 않은 행이다.
  report "확인 표시가 없는 테스트(스펙 확인) 행 (journal.md 15):" \
    "$(printf '%s\n' "$ver_all" | awk -F'\t' '$3 == "테스트(스펙 확인)" && $4 == 0 {print $2}' | sort -u)"
  if [ -f "$REPORT" ]; then
    report "판정이 없는 성공 기준 (report.md 17):" "$(only "$def_sc" "$use_report")"
    report "판정이 확정되지 않은 성공 기준 (report.md 17):" \
      "$(section "$REPORT" 17 | cell_blank 판정 ID)"
    weak_evidence
  fi
fi

echo "== 사슬 B: 요구사항 -> 구현 -> 검증 =="
if [ -z "$def_fr" ]; then
  echo "  경고: charter.md에 FR ID가 하나도 없다."
  chain=1
else
  if [ -f "$DESIGN" ]; then
    report "구현 기록이 없는 요구사항 (design.md 12):" "$(only "$def_fr" "$use_design")"
    report "charter에 없는데 design이 참조하는 FR:" "$(extra "$def_fr" "$use_design")"
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
report "참조된 ADR에 해당 파일이 없다 (decisions/):" "$(only "$used_adr" "$have_adr")"
[ -n "$have_adr" ] || echo "  결정 기록 없음."
# 아무도 참조하지 않는 ADR 은 잡지 않는다. 단독으로 서는 결정이 정상이다.

# 목록의 줄 수. 빈 문자열이면 0 이다.
n() { printf '%s\n' "$1" | grep -vc '^$'; }

echo "== 진척 =="
# 칸까지 채워진 것만 세고, ID 가 적혀 있기만 한 것은 세지 않는다. 언급만 있고 실측값이나
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
  echo "  미착수 $(n "$todo_fr")개. 착수 순서는 design.md 12 구현 현황에 있다: $(printf '%s' "$todo_fr" | tr '\n' ' ')"
fi

# 사람 확인 대기. 가장 최근 테스트 행을 사람이 확인하지 않았거나(테스트(미확인), 또는
# 확인 표시가 없는 테스트(스펙 확인)), 확인한 뒤에 테스트가 바뀐 ID 다. 판정 근거 강도
# 검사는 17 에 달성이 적힌 뒤에만 돌므로, 진행 중에 사람이 무엇을 확인하면 되는지는 여기서
# 보여 준다. 알리기만 하고 종료 코드에는 넣지 않는다.
if [ -n "$wait_ids" ]; then
  echo "  사람 확인 대기 $(n "$wait_ids")개. 가장 최근 테스트를 사람이 확인하지 않았거나, 확인한 뒤에 테스트가 바뀌었다: $(printf '%s' "$wait_ids" | tr '\n' ' ')"
  [ -z "$stale" ] || printf '%s\n' "$stale" | awk -F'\t' '{ print "    - " $1 ": " $2 }'
fi
if [ -z "$repo_root" ] \
   && printf '%s\n' "$latest" | awk -F'\t' '$3 == 1 { f = 1 } END { exit !f }'; then
  echo "  참고: 문서 디렉터리가 git 저장소 안에 있지 않아, 확인한 뒤에 테스트가 바뀌었는지는 검사하지 못했다."
fi

# 미결 결정. 되돌릴 수 없는데 아직 답이 없는 것이라, 그 영역은 건드리기 전에 정해야 한다.
open_adr=$(grep -lE '^\| *상태 *\|[^|]*미결' "$DOCS"/decisions/*.md 2>/dev/null || true)
if [ -n "$open_adr" ]; then
  echo "  미결 결정 $(n "$open_adr")건. 이 영역을 수정하기 전에 답을 정한다:"
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
  echo "  경고: charter.md 헤더의 프로파일이 M도 L도 아니다. 템플릿 잔재를 지운다."
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
    [ -n "$days" ] && [ "$days" -ge 30 ] && signals="${signals}    - ${days}일 경과 (기준 한 달 초과)"$'\n'
    next=L ;;
  *) next="" ;;
esac

if [ -n "$signals" ]; then
  promote=1
  echo "  $next 승급 조건에 해당한다:"
  printf '%s' "$signals"
  echo "    (기계로 확인하지 못하는 신호: 결정을 뒤집었나 / 다른 사람이 수정하나 / 배포 대상이 있나)"
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
