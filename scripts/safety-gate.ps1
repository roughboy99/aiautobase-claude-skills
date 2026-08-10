#Requires -Version 5.1
<#
    Pre-push scan for credentials and private data in the tracked tree.

    Run before every push:
        pwsh ./scripts/safety-gate.ps1

    Exits 1 on any finding.

    WHY THE PATTERNS LIVE IN A SEPARATE FILE
    A gate that hardcodes "search for this private IP" publishes that private IP -
    the scanner leaks exactly what it exists to catch. So the real patterns live in
    scripts/patterns.local.txt, which is gitignored. Copy patterns.example.txt and
    add your own.

    WHY A MISSING PATTERNS FILE IS A HARD ERROR
    The natural failure here is a gate that finds nothing because it was looking for
    nothing, and cheerfully reports success. Zero patterns loaded is treated as a
    broken gate, not a clean tree.
#>

[CmdletBinding()]
param(
    [string]$RepoRoot     = (Split-Path $PSScriptRoot -Parent),
    [string]$PatternsFile = (Join-Path $PSScriptRoot 'patterns.local.txt'),
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

# --- Built-in patterns: universal, contain no private data, always applied. ---
# Token prefixes REQUIRE a payload. A bare "gho_" in prose is a discussion of a
# token format, not a token, and flagging it trains you to ignore the gate.
$Builtin = [ordered]@{
    'private key body'   = '-{2,}BEGIN [A-Z ]*PRIVATE KEY'
    'GitHub token'       = '\b(gho_|ghp_|ghs_|ghu_|github_pat_)[A-Za-z0-9_]{15,}'
    'Anthropic key'      = '\bsk-ant-[A-Za-z0-9_\-]{20,}'
    'OpenAI key'         = '\bsk-[A-Za-z0-9]{32,}'
    'Google API key'     = '\bAIza[A-Za-z0-9_\-]{30,}'
    'AWS access key'     = '\bAKIA[0-9A-Z]{16}\b'
    'Slack token'        = '\bxox[baprs]-[A-Za-z0-9\-]{10,}'
    'Stripe live key'    = '\b(sk|rk|pk)_live_[A-Za-z0-9]{20,}'
    'HuggingFace token'  = '\bhf_[A-Za-z0-9]{30,}'
    'assigned password'  = '(?i)(password|passwd|passphrase)\s*[=:]\s*["'']?[^\s"''#,}<]{3,}'
    'assigned secret'    = '(?i)(secret|api[_\-]?key|access[_\-]?token|auth[_\-]?token)\s*[=:]\s*["'']?[^\s"''#,}<{]{8,}'
    'private LAN IP'     = '\b(10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})\b'
    'JWT'                = 'eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}'
    'URL credentials'    = '[a-zA-Z][a-zA-Z0-9+.\-]*://[^/\s:@]+:[^/\s@]+@'
}

function Mask([string]$s) {
    $t = $s.Trim()
    if ($t.Length -le 8) { return $t.Substring(0, [Math]::Min(2, $t.Length)) + '***' }
    return $t.Substring(0,4) + '***' + $t.Substring($t.Length - 2, 2) + " [len $($t.Length)]"
}

# --- Load local patterns ----------------------------------------------------
$Local = [ordered]@{}
if (Test-Path $PatternsFile) {
    $n = 0
    foreach ($line in (Get-Content $PatternsFile)) {
        $l = $line.Trim()
        if (-not $l -or $l.StartsWith('#')) { continue }
        $n++
        $Local["local #$n"] = $l
    }
}

if ($Local.Count -eq 0) {
    Write-Host ""
    Write-Host "GATE NOT ARMED" -ForegroundColor Red
    Write-Host ""
    Write-Host "  No local patterns loaded from: $PatternsFile"
    Write-Host ""
    Write-Host "  The built-in patterns catch generic credentials, but not YOUR private"
    Write-Host "  paths, hostnames, or brand strings. Running with zero local patterns"
    Write-Host "  would report a clean tree without having looked for the things most"
    Write-Host "  likely to leak."
    Write-Host ""
    Write-Host "  Fix:  cp scripts/patterns.example.txt scripts/patterns.local.txt"
    Write-Host "        then edit it. It is gitignored."
    Write-Host ""
    exit 1
}

$Patterns = [ordered]@{}
foreach ($k in $Builtin.Keys) { $Patterns[$k] = $Builtin[$k] }
foreach ($k in $Local.Keys)   { $Patterns[$k] = $Local[$k] }

# --- Self-test: prove the gate can actually fire ----------------------------
if ($SelfTest) {
    # The probe is ASSEMBLED FROM FRAGMENTS on purpose. If the full strings were
    # written as literals, this scanner would flag its own source file - and the
    # tempting fix (exclude safety-gate.ps1 from the scan) creates the one blind
    # spot where a real secret could sit forever. No fragment matches on its own.
    $probe = @(
        '10.0.' + '0.42'
        'pass'  + 'word=hunter2'
        'gho'   + '_AAAABBBBCCCCDDDDEEEE'
        'sk-'   + 'ant-AAAABBBBCCCCDDDDEEEEFFFF'
        'https://a' + ':b@c.com'
        'eyJ'   + 'abcdefghij.klmnopqrst'
    ) -join ' '
    $fired = @($Builtin.Keys | Where-Object { $probe -match $Builtin[$_] })
    Write-Host ""
    Write-Host "SELF-TEST" -ForegroundColor Cyan
    Write-Host "  built-in patterns that fired on the probe: $($fired.Count)"
    foreach ($f in $fired) { Write-Host "    - $f" }
    if ($fired.Count -lt 5) {
        Write-Host "  FAIL - expected at least 5. The gate is broken." -ForegroundColor Red
        exit 1
    }
    Write-Host "  PASS - gate is live." -ForegroundColor Green
}

# --- Scan the tracked tree --------------------------------------------------
Push-Location $RepoRoot
try {
    $tracked = @(git ls-files)
    if ($LASTEXITCODE -ne 0) { throw "git ls-files failed. Is $RepoRoot a git repo?" }
} finally {
    Pop-Location
}

$findings = @()

foreach ($rel in $tracked) {
    $full = Join-Path $RepoRoot $rel
    if (-not (Test-Path $full)) { continue }

    $leaf = Split-Path $rel -Leaf
    if ($leaf -eq '.env' -or ($leaf -like '.env.*' -and $leaf -ne '.env.example')) {
        $findings += [pscustomobject]@{ Pattern = 'credential file tracked'; File = $rel; Line = 0; Match = '(entire file)' }
    }

    $i = 0
    foreach ($line in (Get-Content $full -ErrorAction SilentlyContinue)) {
        $i++
        foreach ($name in $Patterns.Keys) {
            $m = [regex]::Match($line, $Patterns[$name])
            if ($m.Success) {
                $findings += [pscustomobject]@{ Pattern = $name; File = $rel; Line = $i; Match = (Mask $m.Value) }
            }
        }
    }
}

# --- Report ----------------------------------------------------------------
Write-Host ""
Write-Host "SAFETY GATE" -ForegroundColor Cyan
Write-Host "  repo:     $RepoRoot"
Write-Host "  files:    $($tracked.Count) tracked"
Write-Host "  patterns: $($Builtin.Count) built-in + $($Local.Count) local"
Write-Host ""

if ($findings.Count -eq 0) {
    Write-Host "  CLEAN - safe to push." -ForegroundColor Green
    Write-Host ""
    exit 0
}

Write-Host "  $($findings.Count) FINDING(S) - DO NOT PUSH" -ForegroundColor Red
Write-Host ""
$findings | Sort-Object File, Line | Format-Table -AutoSize Pattern, File, Line, Match
exit 1
