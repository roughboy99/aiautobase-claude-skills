#Requires -Version 5.1
<#
    Installs the aiautobase-claude-skills into ~/.claude/skills/.

    Works two ways:
      1. From a clone:   .\install.ps1
      2. Piped:          irm https://.../install.ps1 | iex

    In the piped case there is no script file on disk, so we shallow-clone to a
    temp dir first. Nothing is ever overwritten - a skill you already have wins.
#>

$ErrorActionPreference = 'Stop'

$RepoUrl = 'https://github.com/roughboy99/aiautobase-claude-skills.git'
$Skills  = @(
    'okthanks','mermaid','plantuml','python-diagrams','go-diagrams','markmap',
    'json-canvas','txt2csv','ssh-remote-connection','write-a-skill','find-skills',
    'director'
)

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok  ($msg) { Write-Host "    $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "    $msg" -ForegroundColor DarkYellow }

# --- Locate the source tree -------------------------------------------------
# $PSScriptRoot is empty when the script is piped into iex, so we cannot rely
# on it. Test for an actual skills/ directory instead.
$tempClone = $null
$sourceDir = $null

if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'skills'))) {
    $sourceDir = $PSScriptRoot
    Write-Step "Installing from local clone: $sourceDir"
}
else {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "git is required to install this way. Install git, or clone the repo manually and run .\install.ps1 from inside it."
    }
    $tempClone = Join-Path ([System.IO.Path]::GetTempPath()) ("aiab-skills-" + [guid]::NewGuid().ToString('N').Substring(0,8))
    Write-Step "Downloading $RepoUrl"
    git clone --depth 1 --quiet $RepoUrl $tempClone
    if ($LASTEXITCODE -ne 0) { throw "git clone failed." }
    $sourceDir = $tempClone
}

$srcSkills = Join-Path $sourceDir 'skills'
if (-not (Test-Path $srcSkills)) { throw "No skills/ directory found in $sourceDir" }

# --- Target ----------------------------------------------------------------
$claudeHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$target     = Join-Path $claudeHome '.claude\skills'

Write-Step "Target: $target"
if (-not (Test-Path $target)) {
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Write-Ok "created $target"
}

# --- Install ---------------------------------------------------------------
$installed = @()
$skipped   = @()

Write-Step "Installing skills"
foreach ($s in $Skills) {
    $from = Join-Path $srcSkills $s
    $to   = Join-Path $target   $s

    if (-not (Test-Path $from)) { Write-Skip "$s - not in this repo, skipping"; continue }

    if (Test-Path $to) {
        $skipped += $s
        Write-Skip "$s - already installed, left untouched"
    } else {
        Copy-Item $from $target -Recurse -Force
        $installed += $s
        Write-Ok "$s"
    }
}

# --- okthanks config -------------------------------------------------------
$okDir     = Join-Path $target 'okthanks'
$okConfig  = Join-Path $okDir 'config.json'
$okExample = Join-Path $okDir 'config.example.json'
$needsSetup = $false

if ((Test-Path $okExample) -and -not (Test-Path $okConfig)) {
    Copy-Item $okExample $okConfig
    $needsSetup = $true
}

# --- Cleanup ---------------------------------------------------------------
if ($tempClone -and (Test-Path $tempClone)) {
    Remove-Item $tempClone -Recurse -Force -ErrorAction SilentlyContinue
}

# --- Summary ---------------------------------------------------------------
Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "  installed: $($installed.Count)$(if ($installed) { ' - ' + ($installed -join ', ') })"
if ($skipped.Count -gt 0) {
    Write-Host "  skipped:   $($skipped.Count) - $($skipped -join ', ')" -ForegroundColor DarkYellow
    Write-Host "             (you already had these; your versions were kept)" -ForegroundColor DarkYellow
}

if ($needsSetup) {
    Write-Host ""
    Write-Host "One more step - okthanks needs two paths before it will run:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Edit: $okConfig"
    Write-Host ""
    Write-Host '    "vault_path":     your Obsidian vault root'
    Write-Host '    "workspace_root": the folder your projects live under'
    Write-Host ""
    Write-Host "Then say 'ok thanks' at the end of a Claude Code session."
}
