#!/usr/bin/env pwsh
# 각 스킬 디렉터리를 dist\<name>.skill 로 압축한다. claude.ai 계정 업로드용.
# 인자로 스킬 이름을 받고, 없으면 전부 압축한다. Windows 판.
#
# POSIX 판은 zip 또는 python3 를 쓰는데 Windows 에는 둘 다 기본 탑재가 아니다.
# Git for Windows 에도 unzip.exe 만 있고 zip.exe 는 없다. 그래서 .NET 내장
# ZipArchive 로 직접 만든다. 외부 의존이 0 이다.
#
# Compress-Archive 를 쓰지 않는 이유: 항목 경로를 역슬래시로 넣는다. ZIP 규격은
# 슬래시라서 업로더가 'skill\SKILL.md' 를 디렉터리 없는 파일명 하나로 볼 수 있다.
# POSIX 판과 바이트 구조가 갈리면 안 되므로 직접 쓴다.
#
#   powershell -ExecutionPolicy Bypass -File scripts\pack.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\pack.ps1 project-doc-framework

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Names
)

$ErrorActionPreference = 'Stop'

# 이 파일은 UTF-8 BOM 으로 저장해야 한다. PowerShell 5.1 은 BOM 없는 .ps1 을
# ANSI 코드페이지로 읽어서 한글 문자열이 깨진다.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

Add-Type -AssemblyName System.IO.Compression      | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null

$repo       = Split-Path -Parent $PSScriptRoot
$skillsRoot = Join-Path $repo 'plugins\doc-protocols\skills'
$dist       = Join-Path $repo 'dist'

if (-not (Test-Path -LiteralPath $skillsRoot)) {
    Write-Output "오류: $skillsRoot 가 없다."
    exit 1
}

if (-not $Names -or $Names.Count -eq 0) {
    $Names = @(Get-ChildItem -LiteralPath $skillsRoot -Directory | Select-Object -ExpandProperty Name)
}
if ($Names.Count -eq 0) {
    Write-Output '오류: 압축할 스킬이 없다.'
    exit 1
}

New-Item -ItemType Directory -Path $dist -Force | Out-Null
$rootFull = (Resolve-Path -LiteralPath $skillsRoot).Path

foreach ($name in $Names) {
    $dir = Join-Path $skillsRoot $name
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        Write-Output "오류: 그런 스킬이 없다: $name"
        exit 1
    }
    $out = Join-Path $dist "$name.skill"
    if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }

    # 항목 경로는 <name>/... 형태의 슬래시로 넣는다. POSIX 판의 `zip -r out name`
    # 과 같은 구조이고, 파일 순서도 정렬해 맞춘다.
    $files = @(Get-ChildItem -LiteralPath $dir -Recurse -File |
               Where-Object { $_.Name -ne '.DS_Store' } |
               Sort-Object FullName)

    $fs = [System.IO.File]::Open($out, [System.IO.FileMode]::Create)
    try {
        $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($f in $files) {
                $rel   = $f.FullName.Substring($rootFull.Length).TrimStart('\', '/').Replace('\', '/')
                $entry = $zip.CreateEntry($rel, [System.IO.Compression.CompressionLevel]::Optimal)
                $es    = $entry.Open()
                try {
                    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
                    $es.Write($bytes, 0, $bytes.Length)
                } finally { $es.Dispose() }
            }
        } finally { $zip.Dispose() }
    } finally { $fs.Dispose() }

    Write-Output "압축: $out"
}

Write-Output ''
Write-Output 'claude.ai -> Settings -> Capabilities 에서 위 파일을 업로드한다.'
