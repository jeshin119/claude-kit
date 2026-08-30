# claude-kit

개인 Claude 스킬의 단일 진실 원천. 같은 스킬을 WSL 의 Claude Code, Windows
데스크톱 앱, claude.ai 계정 세 표면에 배포한다.

## 왜 저장소가 필요한가

Claude 를 쓰는 표면이 여럿인데 **어느 방향으로도 자동 동기화되지 않는다.**
무엇이 보이는지는 "어느 앱이냐"가 아니라 **세션이 어느 환경에서 도는가**로 갈린다.

| 표면 | 세션이 도는 곳 | 스킬·플러그인 출처 |
|---|---|---|
| WSL 터미널 `claude` | WSL | `/home/jeshin/.claude` + 프로젝트 `.claude/` |
| 데스크톱 앱 · Code 탭 · Local | Windows | `C:\Users\<사용자>\.claude` + 프로젝트 `.claude/` |
| 데스크톱 앱 · Code 탭 · WSL 배포판 | 그 배포판 안 | 배포판의 `~/.claude`. **플러그인은 로드되지 않는다** |
| 데스크톱 앱 · Code 탭 · SSH | 원격 호스트 | 원격 호스트의 `~/.claude` |
| 데스크톱 앱 · Chat · Cowork 탭 | 클라우드 | claude.ai 계정(Customize). `~/.claude` 를 안 읽는다 |
| 클라우드 세션 · 루틴 | 클라우드 | claude.ai 계정 + 레포에 커밋된 `.claude/` |

"데스크톱 앱은 계정 환경, WSL 은 로컬 환경"은 절반만 맞다. 데스크톱 앱은 탭마다
다르다. Chat·Cowork 탭은 스킬·플러그인·커넥터를 계정(사이드바 **Customize**)에서
가져오고 `~/.claude` 를 아예 읽지 않는다. Code 탭은 Claude Code 그 자체라서 로컬을
읽는데, 환경 선택기에서 Local 을 고르면 Windows 홈을, WSL 배포판을 고르면 그
배포판의 홈을 읽는다.

그래서 Windows 네이티브와 WSL 은 `~` 가 따로고, 계정까지 합치면 레지스트리가
셋이다. 셋 다 쓰면 같은 스킬이 서로 다르게 편집된 사본 여러 개로 갈라진다.

해결책은 git 저장소 하나를 원본으로 두고 각 표면으로 내보내는 것이다.

```
                        repo (git)
                             |
     +-----------------------+-----------------------+
     |                       |                       |
 marketplace add        marketplace add         scripts/pack.sh
 ~/claude-kit           jeshin119/claude-kit           |
     v                       v                        v
 WSL 의 Claude Code     Windows 데스크톱 앱      dist/*.skill
 (터미널 CLI)           (Code 탭 · Local)       -> claude.ai 계정 업로드
                                                -> Chat · Cowork · 클라우드
```

### 이 저장소에 직접 걸리는 함정

여기 스킬 둘은 `doc-protocols` **플러그인 안에** 들어 있다. 데스크톱 앱의 WSL
세션은 WSL 홈을 읽으면서도 플러그인을 로드하지 않으므로, 거기서는
`/doc-protocols:project-doc-framework` 가 뜨지 않는다. (공식 문서 기준이고 직접
재현해보지는 않았다.) 데스크톱에서 이 스킬을 쓰려면 Code 탭을 **Local** 환경으로
두고 Windows 쪽에 따로 설치하거나, 개인 스킬로도 노출한다.

```bash
ln -s ~/claude-kit/plugins/doc-protocols/skills/project-doc-framework \
      ~/.claude/skills/project-doc-framework
```

Claude Code 는 개인 스킬 위치의 심링크를 따라간다. 대신 플러그인 스킬
(`/doc-protocols:project-doc-framework`)과 개인 스킬(`/project-doc-framework`)이
목록에 둘 다 뜬다. 이름 충돌은 아니지만 설명이 두 번 실린다.

## 구조

```
claude-kit/
├── .claude-plugin/marketplace.json      마켓플레이스 정의 (이름: claude-kit)
├── plugins/doc-protocols/
│   ├── .claude-plugin/plugin.json       플러그인 정의
│   ├── commands/                        /doc-init, /doc-log
│   ├── hooks/
│   │   ├── hooks.json                   Stop 훅 등록
│   │   └── journal_reminder.py          발동 조건 넷을 판단하는 본체
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

### WSL (터미널 CLI)

```bash
git clone git@github.com:jeshin119/claude-kit.git ~/claude-kit
cd ~/claude-kit
./scripts/link.sh          # ~/.claude/CLAUDE.md 심링크
./scripts/bootstrap.sh     # 서드파티 플러그인 3개 복원 (새 환경에서만)
```

그다음 Claude Code 안에서:

```
/plugin marketplace add ~/claude-kit
/plugin install doc-protocols@claude-kit
```

### Windows 데스크톱 앱 (Code 탭 · Local)

`C:\Users\<사용자>\.claude` 는 WSL 쪽과 완전히 별개다. 같은 저장소를 원본으로
쓰되 **로컬 경로가 아니라 GitHub 경유로** 붙인다. Windows 에서 WSL 파일
(`\\wsl.localhost\...`)에 접근하면 네트워크 파일시스템을 타서 느리고 파일 감시가
깨진다는 것이 공식 문서의 설명이다. 마켓플레이스 소스로 그 경로를 줬을 때 실제로
어떻게 되는지는 확인해보지 않았다.

앱의 Code 탭에서 Local 세션을 열고:

```
/plugin marketplace add jeshin119/claude-kit
/plugin install doc-protocols@claude-kit
```

GitHub 경유이므로 **push 한 것까지만 반영된다.** `git push` 를 먼저 한다.

`shared/CLAUDE.md` 는 `link.sh` 가 Windows 에서 안 돈다. Windows 쪽 저장소 사본을
따로 두고 관리자 권한 `cmd` 에서 심링크를 걸거나, 그냥 복사한다.

```
mklink "%USERPROFILE%\.claude\CLAUDE.md" "<저장소 경로>\shared\CLAUDE.md"
```

복사하면 원본이 갈라진다. 고칠 때마다 다시 복사한다는 뜻이다.

서드파티 3개(`humanize-korean`, `frontend-design`, `andrej-karpathy-skills`)도
Windows 쪽에는 따로 깔아야 한다. `bootstrap.sh` 를 Git Bash 에서 돌리거나, 앱의
플러그인 브라우저에서 마켓플레이스를 손으로 추가한다.

### claude.ai 계정

```bash
./scripts/pack.sh
```

`dist/*.skill` 을 데스크톱 앱 사이드바 **Customize**, 또는 claude.ai 스킬 설정에
업로드한다. 자세한 제약은 [계정과 로컬 사이 동기화](#계정과-로컬-사이-동기화)를 본다.

## 계정과 로컬 사이 동기화

### 계정 → 로컬 (WSL · Windows)

**스킬은 된다.** 계정에 켜 둔 스킬을 로컬로 내려받으려면 비대화 모드 실행이 한 번
필요하다. 대화형 세션은 절대 스스로 내려받지 않는다.

```bash
CLAUDE_CODE_SYNC_SKILLS=1 claude -p "사용 가능한 스킬을 나열해라"
```

- 프롬프트 내용은 상관없다. 받아오는 것이 목적이다.
- `~/.claude/skills/synced/` 에 떨어진다. `synced` 는 예약된 이름이라 여기에 직접
  쓴 스킬은 무시된다.
- 이후 대화형 세션은 환경변수 없이도 그 디렉터리에서 읽는다. `/skills` 목록에
  `claude.ai sync` 로 묶여 나온다.
- **붙어 있는 연결이 아니다.** 계정에서 스킬을 고치거나 켤 때마다 위 명령을 다시
  돌려야 한다.
- 이름이 겹치면 로컬이 이긴다. 빌트인·번들·개인·프로젝트·플러그인 스킬 중 하나라도
  같은 이름이면 동기화된 쪽은 건너뛴다. 대소문자·공백·전각 문자는 같은 이름으로
  친다.
- 동기화된 스킬 본문의 `` !`명령` `` 은 내 기계에서 실행되지 않는다.
- 계정에서 스킬을 끄면 다음 동기화 때 `synced/` 에서 사라진다. 손으로 지우면
  다음 동기화가 다시 받아온다.

**플러그인은 안 된다.** 계정에 켠 플러그인은 Cowork·클라우드 세션에서만
`~/.claude/plugins/synced/` 로 내려와 `<이름>@synced` 로 로드된다. 내 터미널
세션과 데스크톱 Local 세션에서는 로드되지 않는다. 로컬에서 쓰려면 마켓플레이스에서
직접 깐다. 이 저장소가 `bootstrap.sh` 로 서드파티 마켓플레이스 등록을 복원하는
이유가 이것이다.

### 로컬 (WSL) → 계정

플러그인을 통째로 올리는 경로는 없다. **스킬 단위로 올린다.**

```bash
./scripts/pack.sh                    # dist/*.skill 생성
./scripts/pack.sh project-doc-framework   # 하나만
```

`dist/*.skill` 을 데스크톱 앱 사이드바 **Customize**, 또는 claude.ai 스킬 설정에
업로드한다. 여기 올린 것이 Chat·Cowork·클라우드 세션·루틴이 보는 스킬이다.

업로드는 frontmatter 를 여섯 필드로 제한한다 — `name`, `description`, `license`,
`compatibility`, `metadata`, `allowed-tools`. 하나라도 벗어나면 무시가 아니라
하드 에러로 업로드가 실패한다.

```
Unexpected key(s) in SKILL.md frontmatter: argument-hint.
Allowed properties are: allowed-tools, compatibility, description, license, metadata, name
```

이 저장소의 `SKILL.md` 둘은 `name` 과 `description` 만 쓰므로 그대로 통과한다.
`commands/doc-init.md` 와 `doc-log.md` 는 `argument-hint` 를 쓰는데 이건 Claude Code
전용이라 계정에 올리면 위 에러가 난다. 커맨드는 업로드 대상이 아니다.

올라가지 않는 것이 더 있다. `${CLAUDE_PLUGIN_ROOT}` 치환, 본문의 `` !`명령` ``
주입, 그리고 Stop 훅(`journal_reminder.py`)은 플러그인 경로에만 있고 계정 쪽에서는
동작하지 않는다. 계정에 올라간 스킬은 문서 절차 본문만 가진 사본이다.

## 스킬을 수정한 뒤

세 표면 모두 **수동 갱신이 필요하다.** 저장소를 고쳐도 자동으로 퍼지지 않는다.

| 표면 | 갱신 방법 |
|---|---|
| Claude Code (WSL) | `/plugin marketplace update claude-kit` |
| Windows 데스크톱 앱 (Code · Local) | `git push` 먼저. 그다음 앱에서 `/plugin marketplace update claude-kit` |
| claude.ai 계정 | `./scripts/pack.sh <스킬명>` 후 해당 `.skill` 재업로드 |
| 이름을 바꿨을 때 | `update` 만으로는 안 된다. 아래를 본다 |
| 다른 머신 · 백업 | `git commit && git push`. 반영 조건은 아니지만 안 하면 잃는다 |

WSL 은 마켓플레이스 소스가 로컬 디렉터리라 `push` 없이도 `update` 가 먹는다.
Windows 는 GitHub 소스라 `push` 한 것까지만 본다. 이 차이 때문에 "WSL 에서는
되는데 데스크톱에서는 옛날 버전"이 나온다.

### 플러그인이나 스킬 이름을 바꿨을 때

`update` 는 내용만 다시 읽는다. 이름을 바꾸면 옛 이름으로 설치된 것이 그대로
남고 새 이름은 설치된 적이 없어서, 저장소는 멀쩡한데 스킬 목록에는 아무것도
안 뜬다. 지우고 다시 깐다.

```bash
claude plugin uninstall <옛이름>@claude-kit
claude plugin marketplace update claude-kit
claude plugin install <새이름>@claude-kit
claude plugin details <새이름>          # commands·hooks 까지 들어갔는지 확인
```

`~/.claude/plugins/cache/claude-kit/<옛이름>` 이 남으면 직접 지운다.
`claude plugin prune` 은 자동 설치된 의존성만 건드려서 이건 안 지운다.

WSL 과 Windows 데스크톱 앱은 캐시가 각각이므로 **양쪽에서 따로** 해야 한다.
계정 쪽은 옛 이름의 스킬을 Customize 에서 지우고 새 `.skill` 을 올린다.

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
