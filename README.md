# claude-kit

개인 Claude 스킬의 단일 진실 원천. 같은 스킬을 Claude Code와 claude.ai 계정
양쪽에 배포한다.

## 왜 저장소가 필요한가

레지스트리가 두 개인데 **어느 방향으로도 동기화되지 않는다.**

| 레지스트리 | 위치 | 읽는 쪽 |
|---|---|---|
| claude.ai 계정 스킬 | 클라우드 (Settings → Capabilities) | Cowork, 데스크톱 앱, 웹 채팅 |
| Claude Code 스킬 | `~/.claude/skills/` | Claude Code CLI |

Windows 네이티브 Claude Code와 WSL Claude Code는 `~`가 따로라, 둘 다 쓰면 사본이
세 개가 된다. 그 결과 같은 스킬이 서로 다르게 편집된 파일 여러 개로 존재한다.

해결책은 git 저장소 하나를 원본으로 두고 각 표면으로 내보내는 것이다.

```
                repo (git)
                    |
      +-------------+-------------+
      |                           |
/plugin marketplace add     scripts/pack.sh
      v                           v
Claude Code (WSL, 이후 Docker)   dist/*.skill -> claude.ai 업로드
```

## 구조

```
claude-kit/
├── .claude-plugin/marketplace.json      마켓플레이스 정의 (이름: claude-kit)
├── plugins/doc-protocols/
│   ├── .claude-plugin/plugin.json       플러그인 정의
│   ├── commands/                        /doc-init, /doc-log
│   ├── hooks/hooks.json                 Stop 훅 (journal 갱신 상기)
│   └── skills/
│       ├── code-explain-protocol/SKILL.md
│       └── project-doc-framework/
│           ├── SKILL.md
│           ├── references/     18항목 카탈로그, 문체·구조 규칙
│           ├── templates/      charter · design · decision · journal · report
│           └── scripts/        check-trace.sh (추적 사슬 검사)
├── shared/CLAUDE.md                     상시 적용되는 개인 지시사항
└── scripts/
    ├── link.sh        ~/.claude/CLAUDE.md 심링크
    ├── pack.sh        dist/*.skill 생성 (계정 업로드용)
    └── bootstrap.sh   서드파티 플러그인 복원 (새 머신/컨테이너)
```

## 최초 설치

```bash
git clone <이 저장소> ~/claude-kit
cd ~/claude-kit
./scripts/link.sh          # ~/.claude/CLAUDE.md 심링크
./scripts/bootstrap.sh     # 서드파티 플러그인 3개 복원 (새 환경에서만)
```

그다음 Claude Code 안에서:

```
/plugin marketplace add ~/claude-kit
/plugin install doc-protocols@claude-kit
```

계정 쪽은 `./scripts/pack.sh` 실행 후 `dist/*.skill`을
claude.ai → Settings → Capabilities 에 업로드한다.

## 스킬을 수정한 뒤

두 표면 모두 **수동 갱신이 필요하다.** 저장소를 고쳐도 자동으로 퍼지지 않는다.

| 표면 | 갱신 방법 |
|---|---|
| Claude Code (WSL) | `/plugin marketplace update claude-kit` |
| 다른 머신 · 백업 | `git commit && git push`. 반영 조건은 아니지만 안 하면 잃는다 |
| claude.ai 계정 | `./scripts/pack.sh <스킬명>` 후 해당 `.skill` 재업로드 |

## 언어 정책

스킬 본문의 언어는 그 스킬의 출력 언어를 따른다. 한국어를 만들어내는 스킬은
본문과 `description`까지 한국어로 쓴다. 본문이 영어면 생성 시점에 번역 단계가
끼어들고, 거기서 번역투가 샌다.

`description` 안의 한국어 트리거 문구(`"이 코드 설명해줘"`, `"이해가 안 돼"`)와
네거티브 트리거 문구(`"~에는 트리거하지 않는다"`)는 지우지 않는다. 발동 판단이
거기서 나오고, 네거티브 문구가 빠지면 구현 요청에 설명 스킬이 잘못 발동한다.

## 서드파티 플러그인을 넣지 않는 이유

`humanize-korean`, `frontend-design`, `andrej-karpathy-skills`는 각자의
마켓플레이스에 그대로 둔다. fork 하거나 복사해오면 상류 업데이트가 끊긴다.
새 환경에서는 `scripts/bootstrap.sh`가 등록만 복원한다.

서드파티까지 묶는 "통합 등록소"로도 만들지 않는다. 상류가 새 플러그인을 추가해도
이 목록에 손으로 적기 전까지 보이지 않고, 이 저장소의 JSON 하나가 깨지면 개인
스킬까지 함께 사라지는 단일 실패점이 생긴다.

## 스킬 목록

| 스킬 | 하는 일 | 발동하지 않는 경우 |
|---|---|---|
| `code-explain-protocol` | 코드·시스템 설명을 구조 → 퀴즈 → 미니 실험 순서로 진행해, "읽은" 상태가 아니라 "이해한" 상태에 도달시킨다 | 기능 구현, 버그 수정, 리팩토링, 코드 생성 |
| `project-doc-framework` | 프로젝트 문서를 세우고·갱신하고·정리한다. 18개 항목을 갱신 주기가 다른 6개 층으로 나누고, 규모 프로파일(S/M/L)로 만들 파일을 정하고, 추적 사슬로 목적과 검증을 잇는다 | 코드 주석·커밋 메시지, 산문 윤문 |

## 문서 커맨드와 훅

스킬은 요청이 description과 맞을 때 발동한다. 판단에 맡기지 않고 확정적으로
돌리려면 아래를 쓴다.

| | 무엇 | 언제 |
|---|---|---|
| `/doc-init` | 규모를 판정하고 프로파일에 맞는 문서 파일만 만든다 | 프로젝트 시작 |
| `/doc-log` | 이번 세션의 작업과 검증값을 `journal.md`에 붙인다 | 작업을 끝낼 때 |
| Stop 훅 | 오늘 코드를 고쳤는데 journal에 오늘 기록이 없으면 알린다 | 자동 |

훅은 조건 넷을 전부 만족할 때만 발동한다. 재발동이 아니고, `docs/journal.md`가
있고, 거기 오늘 날짜가 없고, git 추적 파일 중 오늘 수정된 것이 있을 때다.
자주 뜨면 무시하게 되고, 무시하기 시작하면 없는 것과 같기 때문이다.

문서 골격은 `docs/`에 만들어진다.

```
docs/
├── charter.md          정의(1~5) + 계약(6~8)     S부터
├── design.md           현행(10~12) 덮어쓰기       M부터
├── decisions/          결정(9) append only        M부터
├── journal.md          기록(13~15) 이번 달        S부터
│   └── journal/YYYY-MM.md   롤오버된 지난 달 작업 로그
└── report.md           종결(16~18)                L부터
```
