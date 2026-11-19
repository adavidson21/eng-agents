<#
.SYNOPSIS
    Start a work item's app once and keep it running for the build (Core 4.15.0).

.DESCRIPTION
    Reads the "## UI checks" table in the repo guide (Start, URL, Ready, Seed) and runs app.mjs in the repo folder
    or its worktree. The app's address and process go to <WorkFolder>\ui\app.json, so every per-task UI check
    (Test-Ui.ps1 -Quick) and Workshop's Try it use the same app. When one is already running for this work
    folder, it is reused. {port} in the table's URL and Start becomes a free port, so builds on one repo never
    collide. Stop it with Stop-UiApp.ps1; /review stops it before its full check.

    This script starts the app itself; that is allowed (the agent never starts servers directly).
    It never fails the calling command. The LAST line printed is always "APP: RUNNING <url>" or "APP: SKIPPED <why>".

.EXAMPLE
    .\Start-UiApp.ps1 -WorkFolder .work\L12-refund-reason -Repo .worktrees\L12-refund-reason\portal-ui -Guide portal-ui\AGENTS.local.md
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$WorkFolder,
    [Parameter(Mandatory = $true)][string]$Repo,
    [Parameter(Mandatory = $true)][string]$Guide,
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"
function Done([string]$Line) { Write-Output $Line; exit 0 }

. (Join-Path $PSScriptRoot "UiCommon.ps1")

if (-not (Test-Path -LiteralPath $Guide)) { Done "APP: SKIPPED no repo guide at $Guide" }
$table = Get-UiTable (Get-Content -LiteralPath $Guide -Raw)
if (-not $table.ContainsKey('url') -or -not $table['url']) { Done "APP: SKIPPED the repo guide has no UI checks table (add one with /onboard-repo)" }
if (-not (Test-Path -LiteralPath $Repo)) { Done "APP: SKIPPED no repo folder at $Repo" }
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { Done "APP: SKIPPED Node is not installed" }

$nodeArgs = @((Join-Path $PSScriptRoot "app.mjs"), "serve", "--cwd", (Resolve-Path -LiteralPath $Repo).Path, "--url", $table['url'], "--out", (Join-Path $WorkFolder "ui"), "--timeout", "$TimeoutSeconds")
if ($table['start']) { $nodeArgs += @("--start", $table['start']) }
if ($table['ready']) { $nodeArgs += @("--ready", $table['ready']) }
if ($table['seed']) { $nodeArgs += @("--seed", $table['seed']) }

$lines = & $node.Source @nodeArgs 2>&1 | ForEach-Object { "$_" }
$last = @($lines | Where-Object { $_ -match '^APP: (RUNNING|SKIPPED)' } | Select-Object -Last 1)
if ($last.Count) { Done $last[0] }
Done "APP: SKIPPED app.mjs printed no result: $((@($lines) | Select-Object -Last 1))"
