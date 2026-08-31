#!/usr/bin/env pwsh
# ~/.claude/CLAUDE.md 를 이 저장소의 shared/CLAUDE.md 로 심링크한다. Windows 판.
# 두 번 실행해도 같은 결과가 되도록 만들었다.
#
# 이 파일이 따로 있는 이유는 bootstrap.ps1 과 다르다. 저쪽은 Python 이 없어서였고
# 이쪽은 Git Bash 의 `ln -s` 가 기본값에서 심링크가 아니라 사본을 만들기 때문이다.
# 성공한 것처럼 보이면서 원본과 갈라지는데, 사본 갈라짐을 막는 것이 이 저장소의
# 존재 이유라 조용한 실패를 그대로 둘 수 없다. 그래서 심링크가 안 되면 실패로
# 끝내고, 사본을 원하면 -Copy 로 명시하게 했다.
#
#   powershell -ExecutionPolicy Bypass -File scripts\link.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\link.ps1 -Copy

[CmdletBinding()]
param(
    # 심링크 대신 사본을 만든다. 개발자 모드도 관리자 권한도 없을 때 쓴다.
    # 사본은 자동 반영되지 않는다. shared/CLAUDE.md 를 고칠 때마다 다시 돌린다.
    # 내용이 같으면 아무것도 하지 않고, 달라졌을 때만 이전 사본을 .bak 으로 남긴다.
    [switch]$Copy
)

$ErrorActionPreference = 'Stop'

# 이 파일은 UTF-8 BOM 으로 저장해야 한다. PowerShell 5.1 은 BOM 없는 .ps1 을
# ANSI 코드페이지로 읽어서 한글 문자열이 깨진다.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$repo = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $repo 'shared\CLAUDE.md'

$claudeHome = if ($env:CLAUDE_HOME) { $env:CLAUDE_HOME } else { Join-Path $HOME '.claude' }
$dst        = Join-Path $claudeHome 'CLAUDE.md'

if (-not (Test-Path -LiteralPath $src)) {
    Write-Output "오류: $src 가 없다."
    exit 1
}
if (-not (Test-Path -LiteralPath $claudeHome)) {
    New-Item -ItemType Directory -Path $claudeHome -Force | Out-Null
}

$srcFull = (Resolve-Path -LiteralPath $src).Path

function Get-LinkTarget {
    # 심링크가 아니면 $null, 심링크면 대상 경로(못 읽으면 빈 문자열)를 준다.
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force
    if (-not ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { return $null }
    if ($item.PSObject.Properties['Target'] -and $item.Target) { return @($item.Target)[0] }
    return ''
}

function Show-NextSteps {
    param([string]$Repo)
    $manifest = Get-Content -LiteralPath (Join-Path $Repo '.claude-plugin\marketplace.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Output ''
    Write-Output 'Claude Code 안에서 아래를 직접 실행해야 한다.'
    Write-Output '데스크톱 앱이면 Code 탭을 Local 환경으로 두고 실행한다.'
    Write-Output ''
    Write-Output "  /plugin marketplace add $Repo"
    # 플러그인이 여럿이다. 마켓플레이스에 있는 것을 전부 낸다.
    foreach ($p in $manifest.plugins) {
        Write-Output "  /plugin install $($p.name)@$($manifest.name)"
    }
}

$done = $false

if (Test-Path -LiteralPath $dst) {
    $target = Get-LinkTarget -Path $dst
    if ($null -ne $target) {
        # 이미 심링크다.
        $same = $false
        if ($target) {
            try { $same = ((Resolve-Path -LiteralPath $target).Path -eq $srcFull) } catch { $same = $false }
        }
        if ($Copy) {
            Write-Output '심링크를 사본으로 바꾼다.'
            Remove-Item -LiteralPath $dst -Force
        } elseif ($same) {
            Write-Output "이미 올바른 심링크다: $dst -> $srcFull"
            $done = $true
        } else {
            Write-Output "다른 대상을 가리키는 심링크를 교체한다: $target"
            Remove-Item -LiteralPath $dst -Force
        }
    } else {
        # 실제 파일이다.
        $identical = ((Get-FileHash -LiteralPath $dst).Hash -eq (Get-FileHash -LiteralPath $src).Hash)
        if ($Copy -and $identical) {
            Write-Output "사본이 이미 최신이다: $dst"
            $done = $true
        } else {
            $backup = "$dst.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
            Move-Item -LiteralPath $dst -Destination $backup
            Write-Output "기존 파일을 백업했다: $backup"
        }
    }
}

if (-not $done) {
    if ($Copy) {
        Copy-Item -LiteralPath $src -Destination $dst -Force
        Write-Output "사본 생성: $dst"
        Write-Warning '사본이라 자동 반영되지 않는다. shared/CLAUDE.md 를 고칠 때마다 이 스크립트를 다시 돌린다.'
    } else {
        try {
            New-Item -ItemType SymbolicLink -Path $dst -Target $srcFull -Force | Out-Null
            Write-Output "심링크 생성: $dst -> $srcFull"
        } catch {
            Write-Output ''
            Write-Output "심링크를 만들지 못했다: $($_.Exception.Message)"
            Write-Output ''
            Write-Output 'Windows 는 둘 중 하나가 있어야 심링크를 만든다.'
            Write-Output '  - 설정 > 개인 정보 및 보안 > 개발자용 > 개발자 모드 켜기 (권장, 재부팅 불필요)'
            Write-Output '  - 또는 관리자 권한 PowerShell 에서 실행'
            Write-Output ''
            Write-Output '둘 다 안 되면 사본으로 간다. 자동 반영은 포기하는 것이다.'
            Write-Output '  powershell -ExecutionPolicy Bypass -File scripts\link.ps1 -Copy'
            exit 1
        }
    }
}

Show-NextSteps -Repo $repo
