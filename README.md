# claude-kit

개인 Claude 스킬의 원본 저장소다. 같은 스킬을 WSL의 Claude Code, Windows 데스크톱 앱,
claude.ai 계정 세 표면에 배포한다.

## 저장소가 필요한 이유

Claude를 쓰는 표면이 여럿인데 로컬 사이에는 어느 방향으로도 자동 동기화가 없다.
자동인 것은 계정에서 로컬로 내려오는 한 방향뿐이고, 그것도 서버가 계정에 기능을 열어
줘야 동작한다(아래 "계정에서 로컬로" 절). 무엇이 보이는지는 어느 앱을 쓰는가가 아니라
세션이 어느 환경에서 실행되는가에 따라 정해진다.

| 표면 | 세션이 실행되는 곳 | 스킬·플러그인 출처 |
|---|---|---|
| WSL 터미널 `claude` | WSL | `/home/jeshin/.claude`와 프로젝트 `.claude/` |
| 데스크톱 앱 · Code 탭 · Local | Windows | `C:\Users\<사용자>\.claude`와 프로젝트 `.claude/` |
| 데스크톱 앱 · Code 탭 · WSL 배포판 | 그 배포판 안 | 배포판의 `~/.claude`. 플러그인은 로드되지 않는다 |
| 데스크톱 앱 · Code 탭 · SSH | 원격 호스트 | 원격 호스트의 `~/.claude` |
| 데스크톱 앱 · Chat · Cowork 탭 | 클라우드 | claude.ai 계정(Customize). `~/.claude`를 읽지 않는다 |
| 클라우드 세션 · 루틴 | 클라우드 | claude.ai 계정과 저장소에 커밋된 `.claude/` |

서버가 계정에 기능을 열어 준 뒤부터는 로컬 홈을 읽는 표면에도 계정에서 내려온
`~/.claude/skills/synced/`와 `~/.claude/plugins/synced/`가 함께 로드된다.

"데스크톱 앱은 계정 환경, WSL은 로컬 환경"이라는 설명은 절반만 맞다. 데스크톱 앱은
탭마다 다르다. Chat 탭과 Cowork 탭은 스킬·플러그인·커넥터를 계정(사이드바
**Customize**)에서 가져오고 `~/.claude`를 아예 읽지 않는다. Code 탭은 Claude Code
그 자체라서 로컬을 읽는데, 환경 선택기에서 Local을 고르면 Windows 홈을, WSL 배포판을
고르면 그 배포판의 홈을 읽는다.

그래서 Windows 네이티브와 WSL은 `~`가 따로 있고, 계정까지 합치면 스킬을 읽는 위치가
셋이다. 셋을 다 쓰면 같은 스킬이 서로 다르게 편집된 사본 여러 개로 나뉜다.

해결책은 git 저장소 하나를 원본으로 두고 각 표면으로 내보내는 것이다.

```
                        repo (git)
                             |
     +-----------------------+-----------------------+
     |                       |                       |
 marketplace add        marketplace add         scripts/pack.sh
 ~/claude-kit           jeshin119/claude-kit           |
     v                       v                        v
 WSL의 Claude Code      Windows 데스크톱 앱      dist/*.skill
 (터미널 CLI)           (Code 탭 · Local)       -> claude.ai 계정 업로드
                                                -> Chat · Cowork · 클라우드
```

### 이 저장소에 해당하는 주의점

이 저장소의 스킬 둘은 각각 `doc-protocols`와 `code-explain-protocol` 플러그인 안에
들어 있다. 데스크톱 앱의 WSL 세션은 WSL 홈을 읽으면서도
플러그인을 로드하지 않으므로, 거기서는 `/doc-protocols:project-doc-framework`가
나타나지 않는다. (공식 문서 기준이고 직접 재현해 보지는 않았다.) 데스크톱에서 이 스킬을
쓰려면 Code 탭을 **Local** 환경으로 두고 Windows 쪽에 따로 설치하거나, 개인 스킬로도
노출한다.

```bash
ln -s ~/claude-kit/plugins/doc-protocols/skills/project-doc-framework \
      ~/.claude/skills/project-doc-framework
```

Claude Code는 개인 스킬 위치의 심링크를 따라가므로 이 방법이 동작한다. 대신 플러그인
스킬(`/doc-protocols:project-doc-framework`)과 개인 스킬(`/project-doc-framework`)이
목록에 둘 다 나타나서, 이름 충돌은 아니어도 설명이 두 번 실린다.

## 구조

```
claude-kit/
├── .claude-plugin/marketplace.json      마켓플레이스 정의 (이름: claude-kit)
├── plugins/doc-protocols/               문서 산출물을 만드는 쪽
│   ├── README.md                        층 · 프로파일 · ID · 추적 사슬 개념 설명
│   ├── .claude-plugin/plugin.json       플러그인 정의
│   ├── commands/                        /doc-init, /doc-log
│   ├── hooks/
│   │   ├── hooks.json                   Stop 훅 등록
│   │   └── journal_reminder.py          발동 조건 넷을 판단하는 본체
│   └── skills/project-doc-framework/
│       ├── SKILL.md
│       ├── references/     19개 항목 카탈로그, 문체·구조 규칙
│       ├── templates/      charter · design · decision · journal · report
│       └── scripts/        check-trace.sh (추적 사슬 검사)
├── plugins/code-explain-protocol/       설명만 하고 파일은 만들지 않는 쪽
│   ├── .claude-plugin/plugin.json
│   └── skills/code-explain-protocol/SKILL.md
├── shared/CLAUDE.md                     상시 적용되는 개인 지시사항
├── bin/csess                            세션 목록 CLI (최근 사용순 정렬)
└── scripts/                          POSIX(.sh)와 Windows(.ps1) 짝으로 둔다
    ├── link.sh       link.ps1       CLAUDE.md · csess 심링크
    ├── pack.sh       pack.ps1       dist/*.skill 생성 (계정 업로드용)
    └── bootstrap.sh  bootstrap.ps1  서드파티 플러그인 복원 (새 머신·컨테이너)
```

`.sh`와 `.ps1`은 같은 일을 하고 같은 결과를 낸다. 어느 쪽을 실행해도 되고, 섞어서
실행해도 된다. 왜 두 벌인지는 [스크립트가 두 벌인 이유](#스크립트가-두-벌인-이유)에
있다.

## 스크립트가 하는 일

세 스크립트는 수정하는 대상이 서로 겹치지 않으므로 순서만 맞으면 된다.

| | 수정하는 것 | 대상 | 실행 시점 |
|---|---|---|---|
| `bootstrap` | `~/.claude/settings.json` 안의 JSON | 다른 저장소에 있는 서드파티 플러그인 | 새 머신이나 컨테이너에서 한 번 |
| `link` | 파일 시스템의 심링크 | 이 저장소가 직접 가진 파일 | 새 환경에서, 그리고 링크가 깨졌을 때 |
| `pack` | `dist/`에 `.skill` 파일 생성 | 이 저장소의 스킬 | claude.ai 계정에 올릴 때 |

`bootstrap`은 마켓플레이스 주소와 활성화할 플러그인 이름을 `settings.json`에 적어
두기만 한다. 실제 내려받기는 Claude Code가 다음 기동 때 한다. 서드파티 코드를 이
저장소로 복사하지 않는 이유는, 각 플러그인이 원래 마켓플레이스에 남아 있어야
업데이트를 계속 받기 때문이다.

`link`는 `shared/CLAUDE.md`와 `bin/csess`를 홈 아래 제자리로 잇는다. 사본이 아니라
심링크이므로 원본이 저장소 한 곳뿐이고, 어느 한쪽만 고쳐져서 내용이 달라지는 일이
없다.

`pack`은 계정에 플러그인을 통째로 올릴 수 없기 때문에 스킬 하나를 `.skill` 파일
하나로 묶는다. 자세한 것은 [계정과 로컬 사이 동기화](#계정과-로컬-사이-동기화)에 있다.

### `~/.claude/settings.json`의 역할

Claude Code가 기동할 때 읽는 사용자 전역 설정 파일이다. 모델과 테마 같은 개인 취향과,
어떤 마켓플레이스를 알고 있고 어떤 플러그인을 켤 것인가가 여기 들어 있다. `bootstrap`이
고치는 것은 뒤쪽 두 키다.

```jsonc
{
  "model": "opus",
  "enabledPlugins": {              // 켤 플러그인. "플러그인명@마켓플레이스명"
    "doc-protocols@claude-kit": true
  },
  "extraKnownMarketplaces": {      // 플러그인을 어디서 가져오는가
    "claude-kit": { "source": { "source": "directory", "path": "/home/jeshin/claude-kit" } },
    "im-not-ai":  { "source": { "source": "github", "repo": "epoko77-ai/im-not-ai" } }
  }
}
```

`source`가 `directory`면 그 로컬 clone이 원본이므로 clone을 최신으로 두어야 하고,
`github`면 그쪽 저장소에서 바로 받는다. 이 저장소의 플러그인은 `link`가 마지막에
출력하는 `/plugin marketplace add`로 등록하므로 `bootstrap`이 적지 않는다.

작업 폴더별 설정은 `.claude/settings.json`과 `.claude/settings.local.json`으로 따로
있다. 셋 다 읽지만 키마다 적용 범위가 달라서, 전역에서만 적용되는 키가 있다.
([계정에서 로컬로](#계정에서-로컬로-wsl--windows) 절의 `syncClaudeAiSkills`가 그런
경우다.)

`bootstrap`은 이 파일을 고치기 전에 `.bak.<타임스탬프>`를 먼저 남기고, 바꿀 것이
없으면 백업도 지운다. JSON이 이미 깨져 있으면 수정하지 않고 오류로 끝난다.

## 최초 설치

### WSL (터미널 CLI)

```bash
git clone git@github.com:jeshin119/claude-kit.git ~/claude-kit
cd ~/claude-kit
./scripts/link.sh          # ~/.claude/CLAUDE.md, ~/.local/bin/csess 심링크
./scripts/bootstrap.sh     # 서드파티 플러그인 3개 복원 (새 환경에서만)
```

그다음 Claude Code 안에서 다음을 실행한다.

```
/plugin marketplace add ~/claude-kit
/plugin install doc-protocols@claude-kit
/plugin install code-explain-protocol@claude-kit
```

`csess`를 이름만으로 실행하려면 `~/.local/bin`이 PATH에 있어야 하는데, 없으면
`link.sh`가 알려 준다. 다른 위치에 두고 싶으면 `CLAUDE_KIT_BIN`으로 바꾼다.

### Windows 데스크톱 앱 (Code 탭 · Local)

`C:\Users\<사용자>\.claude`는 WSL 쪽과 완전히 별개다. 설치에는 Python도 Git Bash도
필요 없고, Windows에 항상 있는 PowerShell 5.1로 끝난다.

```powershell
git clone https://github.com/jeshin119/claude-kit.git $HOME\claude-kit
```

```powershell
powershell -ExecutionPolicy Bypass -File $HOME\claude-kit\scripts\bootstrap.ps1
```

```powershell
powershell -ExecutionPolicy Bypass -File $HOME\claude-kit\scripts\link.ps1
```

`link.ps1`은 심링크를 만든다. Windows에서 심링크를 만들려면 **개발자 모드**(설정 >
개인 정보 및 보안 > 개발자용)를 켜거나 관리자 권한이 있어야 한다. 둘 다 없으면
스크립트가 안내를 출력하고 실패로 끝나며, 조용히 사본을 만들지 않는다. 사본을 원하면
다음처럼 명시한다.

```powershell
powershell -ExecutionPolicy Bypass -File $HOME\claude-kit\scripts\link.ps1 -Copy
```

Windows는 확장자 없는 `csess`를 그대로 실행하지 못한다. 그래서 `link.ps1`이 같은
자리에 `csess.cmd` 한 줄짜리 실행 껍데기를 만든다. 껍데기는 원본을 호출하기만 하므로
심링크와 달리 원본과 달라질 것이 없다.

사본은 자동으로 반영되지 않으므로 `shared/CLAUDE.md`나 `bin/csess`를 고칠 때마다 다시
실행해야 한다. 내용이 같으면 아무 일도 하지 않으므로 반복 실행해도 `.bak`이 쌓이지
않는다.

마지막으로 앱의 Code 탭에서 **Local** 세션을 열고(WSL 배포판이 아니다) 다음을
실행한다.

```
/plugin marketplace add C:\Users\<사용자>\claude-kit
/plugin install doc-protocols@claude-kit
/plugin install code-explain-protocol@claude-kit
```

로컬 clone을 소스로 쓰면 WSL과 구조가 같아지고 `git pull` 한 번으로 플러그인과
`CLAUDE.md`가 함께 최신이 된다. clone 없이 GitHub 소스로 붙일 수도 있다.

```
/plugin marketplace add jeshin119/claude-kit
```

이쪽은 `git pull`이 필요 없는 대신 push한 것까지만 반영되고, `CLAUDE.md`를 따로
가져올 방법도 없다.

WSL 파일(`\\wsl.localhost\...`)을 소스로 주지는 않는다. 네트워크 파일시스템을 거쳐서
느리고 파일 감시가 깨진다는 것이 공식 문서의 설명인데, 실제 동작은 확인해 보지 않았다.

### claude.ai 계정

```bash
./scripts/pack.sh
```

`dist/*.skill`을 데스크톱 앱 사이드바 **Customize**, 또는 claude.ai 스킬 설정에
업로드한다. 자세한 제약은 [계정과 로컬 사이 동기화](#계정과-로컬-사이-동기화)에 있다.

## 새 환경으로 이식

환경마다 다른 것은 스크립트 확장자와 심링크 권한뿐이고, 순서는 어디서나 같다.

| 환경 | 스크립트 | 미리 있어야 하는 것 |
|---|---|---|
| WSL · Linux · macOS | `.sh` | `bash`, `python3`, `git` |
| Windows (PowerShell) | `.ps1` | `git`만. PowerShell 5.1은 Windows에 기본 탑재된다 |
| Docker 컨테이너 | `.sh` | `bash`, `python3`, `git`. 로그인은 별도다 |

설치는 세 단계다.

1. **clone**. 어디에 두든 상관없다. 아래는 홈 기준이다.
2. **`bootstrap`**. 서드파티 마켓플레이스와 플러그인 등록을 복원한다. 실제
   내려받기는 Claude Code가 다음 기동 때 한다.
3. **`link`**. `~/.claude/CLAUDE.md`와 `~/.local/bin/csess`를 저장소로 잇는다.

그다음 Claude Code 안에서 개인 플러그인을 설치한다. 이 줄들은 `link`가 마지막에
출력하므로 그대로 복사하면 된다.

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

세 스크립트 모두 두 번 실행해도 같은 결과가 된다. 실패한 것 같으면 다시 실행하면
된다.

### 이식 확인

```
/plugin
```

`doc-protocols`, `code-explain-protocol`, `andrej-karpathy-skills`, `frontend-design`,
`humanize-korean` 다섯이 enabled여야 한다. 그다음 `/doc-protocols:project-doc-framework`, `/doc-init`, `/doc-log`가 실제로
나타나는지 본다.
`CLAUDE.md`는 새 세션에서 지시가 적용되는지로 확인한다.

### 컨테이너에서 주의할 것

계정 동기화(`synced/`)는 로그인 상태에서만 동작한다. 로그인하지 않는 CI 컨테이너에는
아무것도 내려오지 않으므로 이 저장소를 거치는 것이 유일한 방법이다. 반대로
`~/.claude`를 볼륨에 두지 않으면 컨테이너를 지울 때 같이 사라진다. 그래서 복원이 명령
세 줄로 끝나야 한다.

## 계정과 로컬 사이 동기화

### 계정에서 로컬로 (WSL · Windows)

계정에 켜 둔 스킬과 플러그인은 서버가 계정에 기능을 열어 주면 자동으로 내려온다. 켜는
스위치는 내 쪽에 없다.

| | 설정 키 | 내려오는 곳 | 재동기화 |
|---|---|---|---|
| 스킬 | `syncClaudeAiSkills` | `~/.claude/skills/synced/` | 10분마다 |
| 플러그인 | `syncClaudeAiPlugins` | `~/.claude/plugins/synced/` | 기동할 때마다 |

두 키는 `false`로 끄는 용도이지 켜는 용도가 아니다. `true`로 적어도 서버가 열어 주지
않았으면 앞당겨지지 않는다. Claude 계정으로 로그인한 상태에서만
동작한다.

- `~/.claude/settings.json`에 `false`를 적으면 내려받기가 멈추고, 이미 받은 것은
  다음 기동 때 `.trash`로 옮겨져 `cleanupPeriodDays` 후 삭제된다. 다시 켜면 복원이
  아니라 재다운로드다.
- `.claude/settings.local.json`에 `false`를 적으면 그 작업 폴더에서만 막고 숨긴다.
  파일은 옮기지 않는다.
- 프로젝트 설정(`.claude/settings.json`)에서는 읽지 않는다.

이 계정에는 아직 열리지 않았다. 아래 명령으로 확인하면 `synced` 디렉터리가 둘 다
없다.

```bash
ls -d ~/.claude/skills/synced ~/.claude/plugins/synced
```

그때까지는 비대화 모드에서만 동작하는 우회 방법으로 스킬만 손으로 가져올 수 있다.

```bash
CLAUDE_CODE_SYNC_SKILLS=1 claude -p "사용 가능한 스킬을 나열해라"
```

- 프롬프트 내용은 상관없다. 받아오는 것이 목적이다.
- 이후 대화형 세션은 환경변수 없이도 그 디렉터리에서 읽는다. `/skills` 목록에
  `claude.ai sync`로 묶여 나온다.
- 자동이 아니다. 서버가 열어 주기 전까지는 계정에서 스킬을 고치거나 켤 때마다 다시
  실행해야 한다.
- 플러그인 쪽에는 이런 우회가 없다. 서버가 열어 줄 때까지 기다리거나, 마켓플레이스에서
  직접 설치한다.

기능이 열린 뒤든 우회로 받았든 `synced/`의 성질은 같다.

- 주기적으로 덮어써진다. 손으로 편집하면 다음 동기화 때 지워진다. `synced`는 예약된
  이름이라 여기에 직접 쓴 스킬은 무시된다.
- 이름이 겹치면 로컬이 우선한다. 빌트인·번들·개인·프로젝트·플러그인 중 하나라도 같은
  이름이면 동기화된 쪽을 건너뛴다. 플러그인도 같은 이름으로 직접 설치한 것이
  우선한다. 대소문자·공백·전각 문자는 같은 이름으로 취급한다.
- 계정에서 끄면 로컬에서도 사라진다. 손으로 지우면 다음 동기화가 다시 받아온다.
- 동기화된 스킬 본문의 `` !`명령` ``은 내 기계에서 실행되지 않는다.

그래서 계정 동기화가 열려도 이 저장소를 대체하지는 못한다. 계정 동기화는 읽기 전용
배포다. 버전이 없고, 되돌릴 수 없고, 서버가 끄면 같이 사라지고, 훅과 커맨드는 아예
싣지 못한다. `bootstrap.sh`로 서드파티 마켓플레이스 등록을 복원하고 개인 플러그인 둘을
마켓플레이스에서 따로 설치하는 이유가 이것이다.

### 로컬(WSL)에서 계정으로

플러그인을 통째로 올리는 경로는 없으므로 스킬 단위로 올린다.

```bash
./scripts/pack.sh                    # dist/*.skill 생성
./scripts/pack.sh project-doc-framework   # 하나만
```

`dist/*.skill`을 데스크톱 앱 사이드바 **Customize**, 또는 claude.ai 스킬 설정에
업로드한다. 여기 올린 것이 Chat·Cowork·클라우드 세션·루틴이 보는 스킬이다.

업로드는 frontmatter를 `name`, `description`, `license`, `compatibility`, `metadata`,
`allowed-tools` 여섯 필드로 제한하며, 하나라도 벗어나면 무시가 아니라 오류로 업로드가
실패한다.

```
Unexpected key(s) in SKILL.md frontmatter: argument-hint.
Allowed properties are: allowed-tools, compatibility, description, license, metadata, name
```

이 저장소의 `SKILL.md` 둘은 `name`과 `description`만 쓰므로 그대로 통과한다.
`commands/doc-init.md`와 `doc-log.md`는 `argument-hint`를 쓰는데 이것은 Claude Code
전용이라 계정에 올리면 위 오류가 난다. 커맨드는 업로드 대상이 아니다.

올라가지 않는 것이 더 있다. `${CLAUDE_PLUGIN_ROOT}` 치환, 본문의 `` !`명령` ``
주입, 그리고 Stop 훅(`journal_reminder.py`)은 플러그인 경로에만 있고 계정 쪽에서는
동작하지 않는다. 계정에 올라간 스킬은 문서 절차 본문만 가진 사본이다.

## 스킬을 수정한 뒤

저장소를 고쳐도 자동으로 퍼지지 않으므로 세 표면 모두 수동으로 갱신해야 한다.

| 표면 | 갱신 방법 |
|---|---|
| 고친 그 환경 (마켓플레이스 소스가 로컬 clone) | `/plugin marketplace update claude-kit` 뒤에 `claude plugin update doc-protocols@claude-kit`을 실행하고 재시작한다. 2026-09-07에 저장소는 0.4.0인데 설치본이 8월 31일의 0.2.0에 멈춰 있었다. `plugin update`로 올라갔고, `marketplace update`만으로 설치본이 바뀌는지는 확인하지 않았다 |
| 다른 환경 (로컬 clone 소스) | `git push` 뒤 그쪽에서 `git pull`, 그다음 `/plugin marketplace update claude-kit` |
| 다른 환경 (GitHub 소스) | `git push` 뒤 그쪽에서 `/plugin marketplace update claude-kit` |
| `shared/CLAUDE.md` | 심링크면 자동. `link.ps1 -Copy` 사본이면 `link`를 다시 실행한다 |
| `bin/csess` | 심링크면 자동. Windows 사본이면 `link`를 다시 실행한다 |
| claude.ai 계정 | `pack.sh` 또는 `pack.ps1`로 다시 만들어 해당 `.skill`을 재업로드한다 |
| 이름을 바꿨을 때 | `update`만으로는 안 된다. 아래를 본다 |
| 다른 머신 · 백업 | `git commit && git push`. 반영 조건은 아니지만 하지 않으면 잃는다 |

기준은 하나다. 마켓플레이스 소스가 로컬 clone이면 그 clone이 최신이어야 하고, GitHub
소스면 push한 것까지만 본다. 고친 환경에서는 `push` 없이 `update`가 적용되지만 다른
환경은 그렇지 않다. 이 차이 때문에 "여기서는 되는데 저기서는 옛날 버전"이 나온다.

### 플러그인이나 스킬 이름을 바꿨을 때

`update`는 내용만 다시 읽는다. 이름을 바꾸면 옛 이름으로 설치된 것이 그대로 남고 새
이름은 설치된 적이 없어서, 저장소는 멀쩡한데 스킬 목록에는 아무것도 나타나지 않는다.
이때는 지우고 다시 설치한다.

```bash
claude plugin uninstall <옛이름>@claude-kit
claude plugin marketplace update claude-kit
claude plugin install <새이름>@claude-kit
claude plugin details <새이름>          # commands·hooks까지 들어갔는지 확인
```

플러그인 하나를 둘로 나눈 경우도 같다. 남은 쪽은 이름이 그대로여도 캐시에 옛 스킬이
남아 있으므로, 나눈 뒤에는 양쪽 다 지우고 다시 설치한다.

`~/.claude/plugins/cache/claude-kit/<옛이름>`이 남으면 직접 지운다. `claude plugin
prune`은 자동 설치된 의존성만 정리하므로 이것은 지우지 않는다.

WSL과 Windows 데스크톱 앱은 캐시가 각각이므로 양쪽에서 따로 해야 한다. 계정 쪽은 옛
이름의 스킬을 Customize에서 지우고 새 `.skill`을 올린다.

## 언어 정책

스킬 본문의 언어는 그 스킬의 출력 언어를 따른다. 한국어를 만들어내는 스킬은 본문과
`description`까지 한국어로 쓴다. 본문이 영어면 생성 시점에 번역 단계가 끼어들고,
거기서 번역투가 생긴다.

`description` 안의 한국어 트리거 문구(`"이 코드 설명해줘"`, `"이해가 안 돼"`)와
네거티브 트리거 문구(`"~에는 트리거하지 않는다"`)는 지우지 않는다. 발동 판단이
거기서 나오고, 네거티브 문구가 빠지면 구현 요청에 설명 스킬이 잘못 발동한다.

## 서드파티 플러그인을 넣지 않는 이유

`humanize-korean`, `frontend-design`, `andrej-karpathy-skills`는 fork하거나 복사해 오면
상류 업데이트가 끊기므로 각자의 마켓플레이스에 그대로 두고, 새 환경에서는
`scripts/bootstrap.sh`가 등록만 복원한다.

서드파티까지 묶는 "통합 등록소"로도 만들지 않는다. 상류가 새 플러그인을 추가해도 이
목록에 손으로 적기 전까지 보이지 않고, 이 저장소의 JSON 하나가 깨지면 개인 스킬까지
함께 사라지는 단일 실패점이 생긴다.

## 스크립트가 두 벌인 이유

`.sh`는 Git Bash가 있어도 Windows에서 실행되지 않는다. 실제로 확인한 원인은 셋이다.

| 막히는 것 | 무슨 일이 생기나 |
|---|---|
| `python3` 없음 | `bootstrap.sh`가 JSON을 python3로 다룬다. Windows의 `python3.exe`는 2바이트짜리 Microsoft Store 실행 별칭 스텁이라 Store만 열린다 |
| `zip` 없음 | `pack.sh`가 zip 또는 python3를 쓴다. Git for Windows에는 `unzip.exe`만 있고 `zip.exe`가 없다 |
| `ln -s`가 복사 | Git Bash 기본값이 심링크가 아니라 사본이다. 성공한 것처럼 보이면서 원본과 달라진다 |

세 번째가 가장 나쁘다. 사본이 원본과 달라지는 것을 막는 것이 이 저장소의 존재
이유인데, 오류도 나지 않으면서 그 반대가 된다. 그래서 `link.ps1`은 심링크를 만들지
못하면 실패로 끝내고, 사본은 `-Copy`로 명시할 때만 만든다.

Python을 설치하면 `.sh`도 실행되겠지만, 그러면 새 Windows 환경마다 사전 준비가
붙는다. PowerShell 5.1은 Windows에 항상 있고 JSON·zip·심링크가 전부 내장이라 외부
의존이 없다.

두 벌이 어긋나지 않게 맞춘 것은 다음과 같다.

- `.ps1`은 UTF-8 BOM으로 저장한다. PowerShell 5.1은 BOM 없는 `.ps1`을 ANSI
  코드페이지로 읽어서 한글이 깨진다.
- `settings.json`은 BOM 없이 쓴다. `ConvertTo-Json`은 `-Depth 100`을 준다. 기본값이
  2라서 중첩이 깊으면 오류 없이 잘린다.
- `pack.ps1`은 `Compress-Archive`를 쓰지 않는다. 항목 경로를 역슬래시로 넣는데 ZIP
  규격은 슬래시다. `.NET ZipArchive`로 직접 써서 `.sh` 판과 항목 목록·내용이 바이트
  단위로 같음을 확인했다.

두 판은 JSON 들여쓰기 모양만 다르다. `bootstrap.ps1`은 PowerShell 5.1의 정렬 스타일로
쓰지만 의미는 같고, Claude Code가 어차피 다시 쓴다.

## csess: 세션 목록

`claude --resume`은 sdk-cli로 만들어진 세션을 목록에서 빼고, 정렬도 기록 파일의
수정 시각을 쓴다. 그래서 며칠 전에 쓰고 만 세션이 맨 위로 올라온다. 세션을 다시
열거나 관리용 줄이 덧붙기만 해도 파일 수정 시각이 갱신되기 때문이다.

`csess`는 숨겨지는 세션까지 다 보여주고, 사람이 마지막으로 프롬프트를 넣은 시각
순으로 정렬한다. 기록 파일에서 `origin.kind`가 `human`인 줄만 골라 그 timestamp를
쓴다. 도구 실행 결과나 `<ide_opened_file>` 같은 자동 첨부문도 `user` 타입이라
걸러내야 한다.

```bash
csess            # 현재 폴더의 세션 (최근 사용순)
csess -a         # 모든 프로젝트
csess -r         # 번호로 골라 바로 resume
csess -m         # 파일 수정 시각순 (예전 방식)
csess 검색어      # 제목·첫 프롬프트로 거르기
```

두 시각이 30분 넘게 벌어진 세션만 `(파일 N 전)`을 같이 출력한다.

```
  3. doc-protocols 플러그인 업데이트
     14시간 전 (파일 2시간 전) · 123턴 · 748KB · claude-vscode
     85741005-409a-447f-9a61-a83418c427b0
```

`claude-vscode` · `claude-desktop` · `cli`는 그 세션을 어디서 썼는지다. VS Code
확장과 데스크톱 앱이 같은 `~/.claude/projects`에 쓰기 때문에 한 목록에 섞여 나온다.

`origin` 필드가 없는 판본으로 만든 세션은 사람 턴을 찾지 못한다. 그때만 파일 수정
시각으로 되돌아가고, `(파일 …)` 표기는 출력하지 않는다.

## 스킬 목록

`project-doc-framework`가 쓰는 층·프로파일·ID·추적 사슬이 무엇인지는
[plugins/doc-protocols/README.md](plugins/doc-protocols/README.md)에 있다.

| 스킬 | 플러그인 | 하는 일 | 발동하지 않는 경우 |
|---|---|---|---|
| `code-explain-protocol` | `code-explain-protocol` | 코드와 시스템을 구조 설명, 퀴즈, 미니 실험 순서로 설명해서, 읽기만 한 상태가 아니라 이해한 상태에 도달시킨다 | 기능 구현, 버그 수정, 리팩토링, 코드 생성 |
| `project-doc-framework` | `doc-protocols` | 프로젝트 문서를 만들고, 갱신하고, 정리한다. 19개 항목을 갱신 주기가 다른 6개 층으로 나누고, 규모 프로파일(M/L)로 만들 파일을 정하고, 추적 사슬로 목적과 검증을 잇는다 | 코드 주석·커밋 메시지, 산문 윤문 |

스킬 하나를 플러그인 하나에 둔 것은 훅 때문이다. 훅은 플러그인 단위로 등록되므로,
`code-explain-protocol`이 `doc-protocols` 안에 있으면 코드 설명만 쓰는 자리에도
journal 리마인더 Stop 훅이 따라붙는다.

## 문서 커맨드와 훅

스킬은 요청이 description과 맞을 때 발동하므로, 판단에 맡기지 않고 확실하게 실행하려면
아래를 쓴다.

| | 무엇 | 언제 |
|---|---|---|
| `/doc-init` | 규모를 판정하고 프로파일에 맞는 문서 파일만 만든다 | 프로젝트 시작 |
| `/doc-log` | 이번 세션의 작업과 검증값을 `journal.md`에 붙인다 | 작업을 끝낼 때 |
| Stop 훅 | 오늘 코드를 수정했는데 journal에 오늘 기록이 없으면 알린다 | 자동 |

훅은 조건 넷을 전부 만족할 때만 발동한다. 재발동이 아니고, `journal.md`가 있고,
거기에 오늘 날짜가 없고, git 추적 파일 중 오늘 수정된 것이 있을 때다. 자주 표시되면
무시하게 되고, 무시하기 시작하면 없는 것과 같기 때문이다.

문서 골격은 `docs/`에 만들어진다.

```
docs/
├── charter.md          정의(1~6) + 계약(7~9)      M부터
├── design.md           현행(11~13) 덮어쓰기       M부터
├── decisions/          결정(10) 추가만 한다        M부터
├── journal.md          기록(14~16) 이번 달         M부터
│   └── journal/YYYY-MM.md   지난달로 옮긴 작업 로그와 검증 기록
└── report.md           종결(17~19)                종료·보류 시. 19는 L만
```
