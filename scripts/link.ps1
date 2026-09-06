#!/usr/bin/env pwsh
# 이 저장소의 파일을 홈 아래 제자리로 심링크한다. Windows 판.
#
#   shared\CLAUDE.md -> ~\.claude\CLAUDE.md
#   bin\csess        -> ~\.local\bin\csess  (+ 같은 자리에 csess.cmd 실행 껍데기)
#
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
    # 사본은 자동 반영되지 않는다. 원본을 고칠 때마다 다시 돌린다.
    # 내용이 같으면 아무것도 하지 않고, 달라졌을 때만 이전 사본을 .bak 으로 남긴다.
    [switch]$Copy
)

$ErrorActionPreference = 'Stop'

# 이 파일은 UTF-8 BOM 으로 저장해야 한다. PowerShell 5.1 은 BOM 없는 .ps1 을
# ANSI 코드페이지로 읽어서 한글 문자열이 깨진다.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$repo = Split-Path -Parent $PSScriptRoot

$claudeHome = if ($env:CLAUDE_HOME) { $env:CLAUDE_HOME } else { Join-Path $HOME '.claude' }
$binDir     = if ($env:CLAUDE_KIT_BIN) { $env:CLAUDE_KIT_BIN } else { Join-Path $HOME '.local\bin' }

function Get-LinkTarget {
    # 심링크가 아니면 $null, 심링크면 대상 경로(못 읽으면 빈 문자열)를 준다.
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force
    if (-not ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { return $null }
    if ($item.PSObject.Properties['Target'] -and $item.Target) { return @($item.Target)[0] }
    return ''
}

function New-KitLink {
    param([string]$Src, [string]$Dst)

    if (-not (Test-Path -LiteralPath $Src)) {
        Write-Output "오류: $Src 가 없다."
        exit 1
    }
    $dstDir = Split-Path -Parent $Dst
    if (-not (Test-Path -LiteralPath $dstDir)) {
        New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    }

    $srcFull = (Resolve-Path -LiteralPath $Src).Path
    $done = $false

    if (Test-Path -LiteralPath $Dst) {
        $target = Get-LinkTarget -Path $Dst
        if ($null -ne $target) {
            # 이미 심링크다.
            $same = $false
            if ($target) {
                try { $same = ((Resolve-Path -LiteralPath $target).Path -eq $srcFull) } catch { $same = $false }
            }
            if ($Copy) {
                Write-Output '심링크를 사본으로 바꾼다.'
                Remove-Item -LiteralPath $Dst -Force
            } elseif ($same) {
                Write-Output "이미 올바른 심링크다: $Dst -> $srcFull"
                $done = $true
            } else {
                Write-Output "다른 대상을 가리키는 심링크를 교체한다: $target"
                Remove-Item -LiteralPath $Dst -Force
            }
        } else {
            # 실제 파일이다.
            $identical = ((Get-FileHash -LiteralPath $Dst).Hash -eq (Get-FileHash -LiteralPath $Src).Hash)
            if ($Copy -and $identical) {
                Write-Output "사본이 이미 최신이다: $Dst"
                $done = $true
            } else {
                $backup = "$Dst.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
                Move-Item -LiteralPath $Dst -Destination $backup
                Write-Output "기존 파일을 백업했다: $backup"
            }
        }
    }

    if ($done) { return }

    if ($Copy) {
        Copy-Item -LiteralPath $Src -Destination $Dst -Force
        Write-Output "사본 생성: $Dst"
        Write-Warning "사본이라 자동 반영되지 않는다. $Src 를 고칠 때마다 이 스크립트를 다시 돌린다."
        return
    }

    try {
        New-Item -ItemType SymbolicLink -Path $Dst -Target $srcFull -Force | Out-Null
        Write-Output "심링크 생성: $Dst -> $srcFull"
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

function New-CsessShim {
    # 확장자 없는 csess 를 Windows 는 그대로 실행하지 못한다. 옆에 껍데기를 둔다.
    # 내용이 바뀌지 않는 한 줄짜리라 심링크로 걸지 않고 그냥 쓴다.
    param([string]$BinDir)

    $shim = Join-Path $BinDir 'csess.cmd'
    $body = @(
        '@echo off',
        'where py >nul 2>nul && (py -3 "%~dp0csess" %*) || (python "%~dp0csess" %*)'
    ) -join "`r`n"
    $cur = if (Test-Path -LiteralPath $shim) { Get-Content -LiteralPath $shim -Raw } else { $null }
    if ($cur -eq "$body`r`n") {
        Write-Output "실행 껍데기가 이미 있다: $shim"
    } else {
        Set-Content -LiteralPath $shim -Value $body -Encoding ASCII
        Write-Output "실행 껍데기 생성: $shim"
    }

    $onPath = ($env:PATH -split ';' | Where-Object { $_.TrimEnd('\') -ieq $BinDir.TrimEnd('\') })
    if (-not $onPath) {
        Write-Output ''
        Write-Output "$BinDir 이 PATH 에 없다. csess 를 이름만으로 부르려면 아래를 한 번 돌린다:"
        Write-Output "  setx PATH `"%PATH%;$BinDir`""
    }
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

New-KitLink -Src (Join-Path $repo 'shared\CLAUDE.md') -Dst (Join-Path $claudeHome 'CLAUDE.md')
New-KitLink -Src (Join-Path $repo 'bin\csess')        -Dst (Join-Path $binDir 'csess')
New-CsessShim -BinDir $binDir

Show-NextSteps -Repo $repo
