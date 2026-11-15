<#
.SYNOPSIS
    Tells /approve whether a gate file changed since the agent wrote its draft.

.DESCRIPTION
    Prints exactly one word:
      unchanged  the file matches its "Draft-hash:" line (approved as the agent wrote it)
      edited     the file changed after the draft was written (the engineer edited it)
      no-hash    the file has no "Draft-hash:" line (written before Core 2.22.0)
    Only the Status and Draft-hash lines are ignored, so run it BEFORE /approve adds any marks.
    Exit code 1 only when the file is missing.

.EXAMPLE
    pwsh -NoProfile -File Test-DraftHash.ps1 -Path .work/12345-export-retry/plan.md
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Path
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "DraftHash.ps1")

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Write-Error "No file at $Path"
    exit 1
}

$text = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path)
$stored = Get-StoredDraftHash -Text $text
if (-not $stored) { Write-Output "no-hash"; exit 0 }
if ((Get-DraftHash -Text $text) -eq $stored) { Write-Output "unchanged" } else { Write-Output "edited" }
