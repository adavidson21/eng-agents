<#
.SYNOPSIS
    Stop the app Start-UiApp.ps1 keeps running for a work item (Core 4.15.0).

.DESCRIPTION
    Reads <WorkFolder>\ui\app.json, stops that process and its children, and removes the record. An app that was
    already running before (the engineer's own dev server) is never stopped, only forgotten.
    It never fails the calling command. The LAST line printed is always "APP: STOPPED", "APP: NONE" or "APP: SKIPPED <why>".

.EXAMPLE
    .\Stop-UiApp.ps1 -WorkFolder .work\L12-refund-reason
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$WorkFolder
)

$ErrorActionPreference = "Stop"
function Done([string]$Line) { Write-Output $Line; exit 0 }

$out = Join-Path $WorkFolder "ui"
if (-not (Test-Path -LiteralPath (Join-Path $out "app.json"))) { Done "APP: NONE" }
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { Done "APP: SKIPPED Node is not installed" }
$lines = & $node.Source (Join-Path $PSScriptRoot "app.mjs") stop --out $out 2>&1 | ForEach-Object { "$_" }
$last = @($lines | Where-Object { $_ -match '^APP: (STOPPED|NONE|SKIPPED)' } | Select-Object -Last 1)
if ($last.Count) { Done $last[0] }
Done "APP: SKIPPED app.mjs printed no result: $((@($lines) | Select-Object -Last 1))"
