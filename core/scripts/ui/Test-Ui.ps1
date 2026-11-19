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

    A per-task check (/do-task, Core 4.15.0): -Quick checks one width (1280) and writes each page's accessibility
    snapshot as text (ui/task-<n>/aria-<page>-1280.txt) for the agent to read; -Pages names the pages (else the
    table's Pages); -Uncommitted skips when the task's uncommitted changes touch no UI files. It uses the build's
    warm app (Start-UiApp.ps1, ui/app.json) when there is one and never stops it.

    This script starts and stops the app itself; that is allowed (the agent never starts servers directly).
    It never fails the calling command: problems in the app are "UI: FAIL", anything that keeps the check
    from running (no table, no Node, no Playwright, the app cannot start locally) is "UI: SKIPPED <why>".
    The LAST line printed is always "UI: PASS ...", "UI: FAIL ..." or "UI: SKIPPED ...".

.EXAMPLE
    .\Test-Ui.ps1 -WorkFolder .work\L12-refund-reason -Repo .worktrees\L12-refund-reason\portal-ui -Guide portal-ui\AGENTS.local.md -Name after -Base origin/main

.EXAMPLE
    .\Test-Ui.ps1 -WorkFolder .work\L12-refund-reason -Repo .worktrees\L12-refund-reason\portal-ui -Guide portal-ui\AGENTS.local.md -Name task-2 -Quick -Pages "/orders/12" -Uncommitted
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$WorkFolder,
    [Parameter(Mandatory = $true)][string]$Repo,
    [Parameter(Mandatory = $true)][string]$Guide,
    [ValidatePattern('^[a-z0-9-]{1,30}$')][string]$Name = "after",
    [string]$Base,
    [int]$TimeoutSeconds = 180,
    [switch]$Quick,
    [string]$Pages,
    [switch]$Uncommitted
)

$ErrorActionPreference = "Stop"
function Done([string]$Line) { Write-Output $Line; exit 0 }

. (Join-Path $PSScriptRoot "UiCommon.ps1")

if (-not (Test-Path -LiteralPath $Guide)) { Done "UI: SKIPPED no repo guide at $Guide" }
$table = Get-UiTable (Get-Content -LiteralPath $Guide -Raw)
if (-not $table.ContainsKey('url') -or -not $table['url']) { Done "UI: SKIPPED the repo guide has no UI checks table (add one with /onboard-repo)" }
if (-not (Test-Path -LiteralPath $Repo)) { Done "UI: SKIPPED no repo folder at $Repo" }

$globs = Get-UiGlobs $table
if ($Uncommitted) {
    if (-not $globs.Count) { Done "UI: SKIPPED the UI checks table has no UI files patterns" }
    $changed = Get-UncommittedFiles $Repo
    if ($null -eq $changed) { Done "UI: SKIPPED could not list the uncommitted changes" }
    $hit = @($changed | Where-Object { $_ -and (Test-Glob $_ $globs) })
    if (-not $hit.Count) { Done "UI: SKIPPED no UI files changed" }
}
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
$pageList = if ($Pages) { $Pages } else { $table['pages'] }
$pages = ($pageList -split ',' | ForEach-Object { $_.Trim().Trim('`') } | Where-Object { $_ }) -join ','
if ($pages) { $nodeArgs += @("--pages", $pages) }
if ($Quick) { $nodeArgs += @("--widths", "1280", "--aria") }
if ($Name -ne 'before' -and (Test-Path -LiteralPath (Join-Path $out "results-before.json"))) { $nodeArgs += @("--compare", "before") }

$lines = & $node.Source @nodeArgs 2>&1 | ForEach-Object { "$_" }
$last = @($lines | Where-Object { $_ -match '^UI: (PASS|FAIL|SKIPPED)' } | Select-Object -Last 1)
if ($last.Count) { Done $last[0] }
Done "UI: SKIPPED the check printed no result: $((@($lines) | Select-Object -Last 1))"
