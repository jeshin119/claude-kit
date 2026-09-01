# claude-kit

개인 Claude 스킬의 단일 진실 원천. 같은 스킬을 WSL 의 Claude Code, Windows
데스크톱 앱, claude.ai 계정 세 표면에 배포한다.

## 왜 저장소가 필요한가

Claude 를 쓰는 표면이 여럿인데 **로컬끼리는 어느 방향으로도 자동 동기화되지
않는다.** 자동인 것은 계정에서 로컬로 내려오는 한 방향뿐이고, 그마저 서버가 계정에
기능을 열어줘야 돈다 (아래 "계정 → 로컬" 절). 무엇이 보이는지는 "어느 앱이냐"가
아니라 **세션이 어느 환경에서 도는가**로 갈린다.

| 표면 | 세션이 도는 곳 | 스킬·플러그인 출처 |
|---|---|---|
| WSL 터미널 `claude` | WSL | `/home/jeshin/.claude` + 프로젝트 `.claude/` |
| 데스크톱 앱 · Code 탭 · Local | Windows | `C:\Users\<사용자>\.claude` + 프로젝트 `.claude/` |
| 데스크톱 앱 · Code 탭 · WSL 배포판 | 그 배포판 안 | 배포판의 `~/.claude`. **플러그인은 로드되지 않는다** |
| 데스크톱 앱 · Code 탭 · SSH | 원격 호스트 | 원격 호스트의 `~/.claude` |
| 데스크톱 앱 · Chat · Cowork 탭 | 클라우드 | claude.ai 계정(Customize). `~/.claude` 를 안 읽는다 |
| 클라우드 세션 · 루틴 | 클라우드 | claude.ai 계정 + 레포에 커밋된 `.claude/` |

로컬 홈을 읽는 표면에는 계정에서 내려온 `~/.claude/skills/synced/` ·
`~/.claude/plugins/synced/` 도 함께 실린다. 서버가 계정에 열어준 뒤부터다.

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

여기 스킬 둘은 플러그인 안에 들어 있다 — `doc-protocols` 에 하나,
`code-explain-protocol` 에 하나. 데스크톱 앱의 WSL 세션은 WSL 홈을 읽으면서도
플러그인을 로드하지 않으므로, 거기서는 `/doc-protocols:project-doc-framework` 가
뜨지 않는다. (공식 문서 기준이고 직접
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
├── plugins/doc-protocols/               문서 산출물을 만드는 쪽
│   ├── README.md                        층·프로파일·ID·추적 사슬 개념 설명
│   ├── .claude-plugin/plugin.json       플러그인 정의
│   ├── commands/                        /doc-init, /doc-log
│   ├── hooks/
│   │   ├── hooks.json                   Stop 훅 등록
│   │   └── journal_reminder.py          발동 조건 넷을 판단하는 본체
│   └── skills/project-doc-framework/
│       ├── SKILL.md
│       ├── references/     19항목 카탈로그, 문체·구조 규칙
│       ├── templates/      charter · design · decision · journal · report
│       └── scripts/        check-trace.sh (추적 사슬 검사)
├── plugins/code-explain-protocol/       설명만 하고 파일은 안 만드는 쪽
│   ├── .claude-plugin/plugin.json
│   └── skills/code-explain-protocol/SKILL.md
├── shared/CLAUDE.md                     상시 적용되는 개인 지시사항
└── scripts/                          POSIX(.sh)와 Windows(.ps1) 짝으로 둔다
    ├── link.sh       link.ps1       ~/.claude/CLAUDE.md 심링크
    ├── pack.sh       pack.ps1       dist/*.skill 생성 (계정 업로드용)
    └── bootstrap.sh  bootstrap.ps1  서드파티 플러그인 복원 (새 머신/컨테이너)
```

`.sh` 와 `.ps1` 은 같은 일을 하고 같은 결과를 낸다. 어느 쪽을 돌려도 되고,
섞어 돌려도 된다. 왜 두 벌인지는 [스크립트가 두 벌인 이유](#스크립트가-두-벌인-이유)를
본다.

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
/plugin install code-explain-protocol@claude-kit
```

### Windows 데스크톱 앱 (Code 탭 · Local)

`C:\Users\<사용자>\.claude` 는 WSL 쪽과 완전히 별개다. **Python 도 Git Bash 도
필요 없다.** Windows 에 항상 있는 PowerShell 5.1 로 끝난다.

```powershell
git clone https://github.com/jeshin119/claude-kit.git $HOME\claude-kit
```

```powershell
powershell -ExecutionPolicy Bypass -File $HOME\claude-kit\scripts\bootstrap.ps1
```

```powershell
powershell -ExecutionPolicy Bypass -File $HOME\claude-kit\scripts\link.ps1
```

`link.ps1` 은 심링크를 만든다. Windows 는 **개발자 모드**(설정 > 개인 정보 및 보안 >
개발자용) 또는 관리자 권한이 있어야 심링크를 만들 수 있다. 둘 다 없으면 스크립트가
안내를 띄우고 **실패로 끝난다.** 조용히 사본을 만들지 않는다. 사본으로 가려면
명시한다.

```powershell
powershell -ExecutionPolicy Bypass -File $HOME\claude-kit\scripts\link.ps1 -Copy
```

사본은 자동 반영되지 않는다. `shared/CLAUDE.md` 를 고칠 때마다 다시 돌려야 한다.
내용이 같으면 아무 일도 하지 않으므로 반복 실행해도 `.bak` 이 쌓이지 않는다.

마지막으로 앱의 Code 탭에서 **Local** 세션을 열고 (WSL 배포판이 아니다):

```
/plugin marketplace add C:\Users\<사용자>\claude-kit
/plugin install doc-protocols@claude-kit
/plugin install code-explain-protocol@claude-kit
```

로컬 clone 을 소스로 쓰면 WSL 과 구조가 같아지고 `git pull` 한 번으로 플러그인과
`CLAUDE.md` 가 함께 최신이 된다. clone 없이 GitHub 소스로 붙일 수도 있다.

```
/plugin marketplace add jeshin119/claude-kit
```

이쪽은 `git pull` 이 필요 없는 대신 **push 한 것까지만 반영된다.** 그리고
`CLAUDE.md` 를 따로 가져올 방법이 없다.

WSL 파일(`\\wsl.localhost\...`)을 소스로 주지는 않는다. 네트워크 파일시스템을
타서 느리고 파일 감시가 깨진다는 것이 공식 문서의 설명이다. 실제 동작은 확인해보지
않았다.

### claude.ai 계정

```bash
./scripts/pack.sh
```

`dist/*.skill` 을 데스크톱 앱 사이드바 **Customize**, 또는 claude.ai 스킬 설정에
업로드한다. 자세한 제약은 [계정과 로컬 사이 동기화](#계정과-로컬-사이-동기화)를 본다.

## 새 환경으로 이식

환경마다 다른 것은 **스크립트 확장자와 심링크 권한**뿐이다. 순서는 어디서나 같다.

| 환경 | 스크립트 | 미리 있어야 하는 것 |
|---|---|---|
| WSL · Linux · macOS | `.sh` | `bash`, `python3`, `git` |
| Windows (PowerShell) | `.ps1` | `git` 만. PowerShell 5.1 은 Windows 기본 탑재 |
| Docker 컨테이너 | `.sh` | `bash`, `python3`, `git`. 로그인은 별도 |

세 단계다.

1. **clone** — 어디에 두든 상관없다. 아래는 홈 기준이다.
2. **`bootstrap`** — 서드파티 마켓플레이스·플러그인 등록을 복원한다. 실제 내려받기는
   Claude Code 가 다음 기동 때 한다.
3. **`link`** — `~/.claude/CLAUDE.md` 를 저장소로 잇는다.

그다음 Claude Code 안에서 개인 플러그인을 깐다. 이 줄들은 `link` 가 마지막에
출력해주므로 그대로 복사하면 된다.

```
/plugin marketplace add <clone 경로>
/plugin install doc-protocols@claude-kit
/plugin install code-explain-protocol@claude-kit
```

POSIX:

```bash
git clone https://github.com/jeshin119/claude-kit.git ~/claude-kit && ~/claude-kit/scripts/bootstrap.sh && ~/claude-kit/scripts/link.sh
```

Windows:

```powershell
git clone https://github.com/jeshin119/claude-kit.git $HOME\claude-kit; & $HOME\claude-kit\scripts\bootstrap.ps1; & $HOME\claude-kit\scripts\link.ps1
```

세 스크립트 모두 **두 번 돌려도 같은 결과**가 된다. 실패한 것 같으면 그냥 다시
돌리면 된다.

### 이식됐는지 확인

```
/plugin
```

`doc-protocols`, `code-explain-protocol`, `andrej-karpathy-skills`,
`frontend-design`, `humanize-korean` 다섯이 enabled 여야 한다. 그다음 스킬과 커맨드가 실제로 노출되는지 본다 —
`/doc-protocols:project-doc-framework`, `/doc-init`, `/doc-log`. `CLAUDE.md` 는
새 세션에서 지시가 먹는지로 확인한다.

### 컨테이너에서 주의할 것

계정 동기화(`synced/`)는 로그인 상태에서만 돈다. 로그인하지 않는 CI 컨테이너에는
아무것도 안 내려오므로 이 저장소 경유가 유일한 길이다. 반대로 `~/.claude` 를 볼륨에
얹지 않으면 컨테이너를 지울 때 같이 사라진다. 그래서 복원이 세 줄로 끝나야 한다.

## 계정과 로컬 사이 동기화

### 계정 → 로컬 (WSL · Windows)

계정에 켜 둔 스킬과 플러그인은 **서버가 계정에 기능을 열어주면 자동으로** 내려온다.
켜는 스위치는 내 쪽에 없다.

| | 설정 키 | 내려오는 곳 | 재동기화 |
|---|---|---|---|
| 스킬 | `syncClaudeAiSkills` | `~/.claude/skills/synced/` | 10분마다 |
| 플러그인 | `syncClaudeAiPlugins` | `~/.claude/plugins/synced/` | 기동할 때마다 |

두 키 모두 **`false` 만 먹는다.** 끄는 용도지 켜는 용도가 아니다. `true` 로 적어도
서버가 안 열어줬으면 앞당겨지지 않는다. Claude 계정으로 로그인한 상태에서만 돈다.

- `~/.claude/settings.json` 에 `false` → 내려받기가 멈추고, 이미 받은 것은 다음
  기동 때 `.trash` 로 옮겨져 `cleanupPeriodDays` 후 삭제된다. 다시 켜면 복원이
  아니라 재다운로드다.
- `.claude/settings.local.json` 에 `false` → 그 작업 폴더에서만 막고 숨긴다.
  파일은 옮기지 않는다.
- 프로젝트 설정(`.claude/settings.json`)에서는 **읽지 않는다.**

**아직 이 계정에는 안 열렸다.** `synced` 디렉터리가 둘 다 없다. 확인은 이걸로 한다.

```bash
ls -d ~/.claude/skills/synced ~/.claude/plugins/synced
```

그때까지는 스킬만 손으로 당겨올 수 있다. 비대화 모드에서만 되는 강제 우회다.

```bash
CLAUDE_CODE_SYNC_SKILLS=1 claude -p "사용 가능한 스킬을 나열해라"
```

- 프롬프트 내용은 상관없다. 받아오는 것이 목적이다.
- 이후 대화형 세션은 환경변수 없이도 그 디렉터리에서 읽는다. `/skills` 목록에
  `claude.ai sync` 로 묶여 나온다.
- **자동이 아니다.** 서버가 열어주기 전까지는 계정에서 스킬을 고치거나 켤 때마다
  다시 돌려야 한다.
- **플러그인 쪽에는 이런 우회가 없다.** 서버가 열어줄 때까지 기다리거나,
  마켓플레이스에서 직접 깐다.

기능이 열린 뒤든 우회로 받았든 `synced/` 의 성질은 같다.

- **주기적으로 덮어써진다.** 손으로 편집하면 다음 동기화 때 날아간다. `synced` 는
  예약된 이름이라 여기에 직접 쓴 스킬은 무시된다.
- **이름이 겹치면 로컬이 이긴다.** 빌트인·번들·개인·프로젝트·플러그인 중 하나라도
  같은 이름이면 동기화된 쪽을 건너뛴다. 플러그인도 같은 이름으로 직접 깔아둔 것이
  우선한다. 대소문자·공백·전각 문자는 같은 이름으로 친다.
- **계정에서 끄면 로컬에서도 사라진다.** 손으로 지우면 다음 동기화가 다시 받아온다.
- 동기화된 스킬 본문의 `` !`명령` `` 은 내 기계에서 실행되지 않는다.

그래서 계정 동기화가 열려도 이 저장소를 대체하지는 못한다. 저쪽은 **읽기 전용
배포**다 — 버전이 없고, 되돌릴 수 없고, 서버가 끄면 같이 사라지고, 훅과 커맨드는
아예 싣지 못한다. `bootstrap.sh` 로 서드파티 마켓플레이스 등록을 복원하고
개인 플러그인 둘을 마켓플레이스에서 따로 까는 이유가 이것이다.

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
| 고친 그 환경 (마켓플레이스 소스가 로컬 clone) | `/plugin marketplace update claude-kit` |
| 다른 환경 (로컬 clone 소스) | `git push` → 그쪽에서 `git pull` → `/plugin marketplace update claude-kit` |
| 다른 환경 (GitHub 소스) | `git push` → 그쪽에서 `/plugin marketplace update claude-kit` |
| `shared/CLAUDE.md` | 심링크면 자동. `link.ps1 -Copy` 사본이면 `link` 를 다시 돌린다 |
| claude.ai 계정 | `pack.sh` / `pack.ps1` 로 다시 만들어 해당 `.skill` 재업로드 |
| 이름을 바꿨을 때 | `update` 만으로는 안 된다. 아래를 본다 |
| 다른 머신 · 백업 | `git commit && git push`. 반영 조건은 아니지만 안 하면 잃는다 |

기준은 하나다 — **마켓플레이스 소스가 로컬 clone 이면 그 clone 이 최신이어야 하고,
GitHub 소스면 push 한 것까지만 본다.** 고친 환경에서는 `push` 없이 `update` 가
먹지만 다른 환경은 그렇지 않다. 이 차이 때문에 "여기서는 되는데 저기서는 옛날
버전"이 나온다.

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

플러그인 하나를 둘로 쪼갠 경우도 같다. 남은 쪽은 이름이 그대로여도 캐시에 옛
스킬이 남아 있으므로, 쪼갠 뒤에는 양쪽 다 지우고 다시 깐다.

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

## 스크립트가 두 벌인 이유

`.sh` 를 Windows 에서 그냥 돌리면 될 것 같지만 안 된다. Git Bash 가 있어도 막힌다.
실제로 확인한 것 셋이다.

| 막히는 것 | 무슨 일이 생기나 |
|---|---|
| `python3` 없음 | `bootstrap.sh` 가 JSON 을 python3 로 다룬다. Windows 의 `python3.exe` 는 **2바이트짜리 Microsoft Store 실행 별칭 스텁**이라 Store 만 열린다 |
| `zip` 없음 | `pack.sh` 가 zip 또는 python3 를 쓴다. Git for Windows 에는 `unzip.exe` 만 있고 `zip.exe` 가 없다 |
| `ln -s` 가 복사 | Git Bash 기본값이 심링크가 아니라 사본이다. **성공한 것처럼 보이면서** 원본과 갈라진다 |

셋째가 제일 나쁘다. 사본 갈라짐을 막는 것이 이 저장소의 존재 이유인데 에러도 안 나고
그 반대가 된다. 그래서 `link.ps1` 은 심링크를 못 만들면 실패로 끝내고, 사본은
`-Copy` 로 명시할 때만 만든다.

Python 을 설치하면 `.sh` 도 돌겠지만, 그러면 새 Windows 환경마다 사전 준비가 붙는다.
PowerShell 5.1 은 Windows 에 항상 있고 JSON·zip·심링크가 전부 내장이라 의존이 0 이다.

두 벌이 갈라지지 않게 맞춘 것:

- `.ps1` 은 **UTF-8 BOM** 으로 저장한다. PowerShell 5.1 은 BOM 없는 `.ps1` 을 ANSI
  코드페이지로 읽어서 한글이 깨진다.
- `settings.json` 은 BOM **없이** 쓴다. `ConvertTo-Json` 은 `-Depth 100` 을 준다.
  기본값이 2 라서 중첩이 깊으면 조용히 잘린다.
- `pack.ps1` 은 `Compress-Archive` 를 쓰지 않는다. 항목 경로를 역슬래시로 넣는데
  ZIP 규격은 슬래시다. `.NET ZipArchive` 로 직접 써서 `.sh` 판과 항목 목록·내용이
  바이트 단위로 같음을 확인했다.

JSON 들여쓰기 모양만 다르다. `bootstrap.ps1` 은 PowerShell 5.1 의 정렬 스타일로
쓴다. 의미는 같고, Claude Code 가 어차피 다시 쓴다.

## 스킬 목록

`project-doc-framework` 가 쓰는 층·프로파일·ID·추적 사슬이 무엇인지는
[plugins/doc-protocols/README.md](plugins/doc-protocols/README.md) 에 있다.

| 스킬 | 플러그인 | 하는 일 | 발동하지 않는 경우 |
|---|---|---|---|
| `code-explain-protocol` | `code-explain-protocol` | 코드·시스템 설명을 구조 → 퀴즈 → 미니 실험 순서로 진행해, "읽은" 상태가 아니라 "이해한" 상태에 도달시킨다 | 기능 구현, 버그 수정, 리팩토링, 코드 생성 |
| `project-doc-framework` | `doc-protocols` | 프로젝트 문서를 세우고·갱신하고·정리한다. 19개 항목을 갱신 주기가 다른 6개 층으로 나누고, 규모 프로파일(S/M/L)로 만들 파일을 정하고, 추적 사슬로 목적과 검증을 잇는다 | 코드 주석·커밋 메시지, 산문 윤문 |

스킬 하나를 플러그인 하나에 둔 것은 훅 때문이다. 훅은 플러그인 단위로 걸려서,
`code-explain-protocol` 이 `doc-protocols` 안에 있으면 코드 설명만 쓰는 자리에도
journal 리마인더 Stop 훅이 따라붙는다.

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
