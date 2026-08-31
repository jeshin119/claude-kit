#!/usr/bin/env pwsh
# 새 머신에서 서드파티 마켓플레이스·플러그인을 복원한다. Windows(PowerShell) 판.
# scripts/bootstrap.sh 와 같은 일을 하고 같은 결과를 낸다.
#
# 이 파일이 따로 있는 이유: POSIX 판은 JSON 을 python3 로 다루는데 Windows 에는
# Python 이 기본 탑재가 아니다. PowerShell 5.1 은 Windows 에 항상 있고
# ConvertFrom-Json / ConvertTo-Json 이 내장이라 외부 의존이 0 이 된다.
#
#   powershell -ExecutionPolicy Bypass -File scripts\bootstrap.ps1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# 이 파일은 UTF-8 BOM 으로 저장해야 한다. PowerShell 5.1 은 BOM 없는 .ps1 을
# ANSI 코드페이지로 읽어서 한글 문자열이 깨진다. 편집기 설정을 확인한다.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# claude-kit 자신은 여기 넣지 않는다. 서드파티 등록만 복원하고 개인 플러그인은
# 마켓플레이스로 따로 깐다. 이 저장소의 JSON 하나가 깨졌을 때 개인 스킬까지
# 함께 사라지는 단일 실패점을 만들지 않기 위해서다. README 를 본다.
$Marketplaces = [ordered]@{
    'karpathy-skills' = [ordered]@{ source = 'github'; repo = 'forrestchang/andrej-karpathy-skills' }
    'im-not-ai'       = [ordered]@{ source = 'github'; repo = 'epoko77-ai/im-not-ai' }
}
# claude-plugins-official 은 Claude Code 에 기본 내장되어 있어 등록이 필요 없다.
$Plugins = @(
    'andrej-karpathy-skills@karpathy-skills'
    'frontend-design@claude-plugins-official'
    'humanize-korean@im-not-ai'
)

function ConvertTo-OrderedHashtable {
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $h = [ordered]@{}
        foreach ($k in $InputObject.Keys) { $h[$k] = ConvertTo-OrderedHashtable $InputObject[$k] }
        return $h
    }
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $h = [ordered]@{}
        foreach ($p in $InputObject.PSObject.Properties) { $h[$p.Name] = ConvertTo-OrderedHashtable $p.Value }
        return $h
    }
    if (($InputObject -is [System.Collections.IEnumerable]) -and ($InputObject -isnot [string])) {
        return ,@($InputObject | ForEach-Object { ConvertTo-OrderedHashtable $_ })
    }
    return $InputObject
}

function Write-JsonFile {
    param([string]$Path, $Value)
    # ConvertTo-Json 의 -Depth 기본값은 2 라서 중첩이 깊으면 조용히 잘린다. 반드시 준다.
    $json = ($Value | ConvertTo-Json -Depth 100) + "`n"
    # settings.json 에 BOM 이 들어가면 파서가 깨질 수 있어 BOM 없는 UTF-8 로 쓴다.
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding $false))
}

$claudeHome = if ($env:CLAUDE_HOME) { $env:CLAUDE_HOME } else { Join-Path $HOME '.claude' }
$settings   = Join-Path $claudeHome 'settings.json'

if (-not (Test-Path -LiteralPath $claudeHome)) {
    New-Item -ItemType Directory -Path $claudeHome -Force | Out-Null
}
if (-not (Test-Path -LiteralPath $settings)) {
    Write-JsonFile -Path $settings -Value ([ordered]@{})
}

try {
    $raw = Get-Content -LiteralPath $settings -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { $raw = '{}' }
    $cfg = ConvertTo-OrderedHashtable (ConvertFrom-Json $raw)
} catch {
    throw "오류: $settings 파싱 실패 - $($_.Exception.Message)"
}
if ($null -eq $cfg) { $cfg = [ordered]@{} }

$backup = "$settings.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
Copy-Item -LiteralPath $settings -Destination $backup

$changed = New-Object System.Collections.Generic.List[string]

if (-not $cfg.Contains('extraKnownMarketplaces')) { $cfg['extraKnownMarketplaces'] = [ordered]@{} }
foreach ($name in $Marketplaces.Keys) {
    $want    = $Marketplaces[$name]
    $current = $null
    if ($cfg['extraKnownMarketplaces'].Contains($name)) {
        $entry = $cfg['extraKnownMarketplaces'][$name]
        if ($entry -and $entry.Contains('source')) { $current = $entry['source'] }
    }
    $same = $false
    if ($current) {
        $same = (($current | ConvertTo-Json -Depth 10 -Compress) -eq ($want | ConvertTo-Json -Depth 10 -Compress))
    }
    if (-not $same) {
        $cfg['extraKnownMarketplaces'][$name] = [ordered]@{ source = $want }
        $changed.Add("마켓플레이스 추가: $name ($($want['repo']))")
    }
}

if (-not $cfg.Contains('enabledPlugins')) { $cfg['enabledPlugins'] = [ordered]@{} }
foreach ($p in $Plugins) {
    if ($cfg['enabledPlugins'][$p] -ne $true) {
        $cfg['enabledPlugins'][$p] = $true
        $changed.Add("플러그인 활성화: $p")
    }
}

if ($changed.Count -gt 0) {
    Write-JsonFile -Path $settings -Value $cfg
    Write-Output "백업: $backup"
    foreach ($c in $changed) { Write-Output "  $c" }
    Write-Output ''
    Write-Output 'Claude Code 를 재시작하면 내려받기가 시작된다.'
} else {
    Remove-Item -LiteralPath $backup -Force
    Write-Output '변경 없음 - 서드파티 플러그인이 이미 전부 등록돼 있다.'
}
