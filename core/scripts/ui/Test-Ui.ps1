<#
.SYNOPSIS
    UI checks for one repo of a work item: start the app, screenshot its pages, check them, stop the app.

.DESCRIPTION
    Reads the "## UI checks" table in the repo guide (Start, URL, Ready, Pages, UI files, Seed) and runs
    check-ui.mjs (Node and Playwright) in the repo folder or its worktree. Screenshots and
    results-<Name>.json go to <WorkFolder>\ui. With -Name after, it compares with the "before" run that
    /start took, when there is one.

    With -Base, it first checks that the change touches UI files (git diff --name-only <Base>...HEAD against
    the table's UI files patterns) and skips when it does not.

    This script starts and stops the app itself; that is allowed (the agent never starts servers directly).
    It never fails the calling command: problems in the app are "UI: FAIL", anything that keeps the check
    from running (no table, no Node, no Playwright, the app cannot start locally) is "UI: SKIPPED <why>".
    The LAST line printed is always "UI: PASS ...", "UI: FAIL ..." or "UI: SKIPPED ...".

.EXAMPLE
    .\Test-Ui.ps1 -WorkFolder .work\L12-refund-reason -Repo .worktrees\L12-refund-reason\portal-ui -Guide portal-ui\AGENTS.local.md -Name after -Base origin/main
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$WorkFolder,
    [Parameter(Mandatory = $true)][string]$Repo,
    [Parameter(Mandatory = $true)][string]$Guide,
    [ValidatePattern('^[a-z0-9-]{1,30}$')][string]$Name = "after",
    [string]$Base,
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"
function Done([string]$Line) { Write-Output $Line; exit 0 }

function Get-UiTable([string]$Text) {
    $rows = @{}
    if (-not $Text) { return $rows }
    $in = $false
    foreach ($line in ($Text -split "\r?\n")) {
        if ($line -match '^\s*##\s+UI checks\s*$') { $in = $true; continue }
        if ($in -and $line -match '^\s*##\s') { break }
        if (-not $in) { continue }
        if ($line -match '^\s*\|\s*([^|]+?)\s*\|\s*(.*?)\s*\|\s*$') {
            $k = $Matches[1].Trim().ToLowerInvariant()
            $v = $Matches[2].Trim()
            if ($k -eq 'field' -or $k -match '^:?-+:?$') { continue }
            $v = ($v -replace '`', '').Trim()
            if ($v -match '^<.*>$' -or $v -match '^TODO') { $v = '' }
            $rows[$k] = $v
        }
    }
    return $rows
}

function Test-Glob([string]$File, [string[]]$Globs) {
    $f = $File -replace '\\', '/'
    foreach ($g in $Globs) {
        $g = ($g.Trim() -replace '\\', '/')
        if (-not $g) { continue }
        $rx = '^' + ([regex]::Escape($g) -replace '\\\*\\\*/', '(.*/)?' -replace '\\\*\\\*', '.*' -replace '\\\*', '[^/]*' -replace '\\\?', '.') + '$'
        if ($f -match $rx) { return $true }
        if ($g -notmatch '/' -and ((Split-Path $f -Leaf) -match $rx)) { return $true }
    }
    return $false
}

if (-not (Test-Path -LiteralPath $Guide)) { Done "UI: SKIPPED no repo guide at $Guide" }
$table = Get-UiTable (Get-Content -LiteralPath $Guide -Raw)
if (-not $table.ContainsKey('url') -or -not $table['url']) { Done "UI: SKIPPED the repo guide has no UI checks table (add one with /onboard-repo)" }
if (-not (Test-Path -LiteralPath $Repo)) { Done "UI: SKIPPED no repo folder at $Repo" }

$globs = @()
if ($table['ui files']) { $globs = $table['ui files'] -split ',' }
if ($Base) {
    if (-not $globs.Count) { Done "UI: SKIPPED the UI checks table has no UI files patterns" }
    $changed = & git -C $Repo diff --name-only "$Base...HEAD" 2>$null
    if ($LASTEXITCODE -ne 0) { Done "UI: SKIPPED could not list the changed files against $Base" }
    $hit = @($changed | Where-Object { $_ -and (Test-Glob $_ $globs) })
    if (-not $hit.Count) { Done "UI: SKIPPED no UI files changed" }
}

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { Done "UI: SKIPPED Node is not installed" }

$out = Join-Path $WorkFolder "ui"
$script = Join-Path $PSScriptRoot "check-ui.mjs"
$nodeArgs = @($script, "--cwd", (Resolve-Path -LiteralPath $Repo).Path, "--url", $table['url'], "--out", $out, "--name", $Name, "--timeout", "$TimeoutSeconds")
if ($table['start']) { $nodeArgs += @("--start", $table['start']) }
if ($table['ready']) { $nodeArgs += @("--ready", $table['ready']) }
if ($table['seed']) { $nodeArgs += @("--seed", $table['seed']) }
$pages = ($table['pages'] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ','
if ($pages) { $nodeArgs += @("--pages", $pages) }
if ($Name -ne 'before' -and (Test-Path -LiteralPath (Join-Path $out "results-before.json"))) { $nodeArgs += @("--compare", "before") }

$lines = & $node.Source @nodeArgs 2>&1 | ForEach-Object { "$_" }
$last = @($lines | Where-Object { $_ -match '^UI: (PASS|FAIL|SKIPPED)' } | Select-Object -Last 1)
if ($last.Count) { Done $last[0] }
Done "UI: SKIPPED the check printed no result: $((@($lines) | Select-Object -Last 1))"
