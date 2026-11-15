<#
.SYNOPSIS
    Stamps a gate file (spec.md, plan.md, bug.md, stories.md, milestones.md, refine.md) with the hash of
    the draft the agent just wrote, so /approve can tell whether the engineer edited it before approving.

.DESCRIPTION
    Writes or replaces one line, "Draft-hash: <12 hex>", right after the first "Status:" line.
    Changes nothing else in the file. Keeps the file's line endings. Prints the line it wrote.
    Run it as the last step after writing or refining a draft. /approve runs Test-DraftHash.ps1.

.EXAMPLE
    pwsh -NoProfile -File Set-DraftHash.ps1 -Path .work/12345-export-retry/spec.md
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

$full = (Resolve-Path -LiteralPath $Path).Path
$text = [System.IO.File]::ReadAllText($full)
$nl = if ($text -match "\r\n") { "`r`n" } else { "`n" }
$hash = Get-DraftHash -Text $text
$line = "Draft-hash: $hash"

if ($text -match '(?mi)^\s*Draft-hash\s*:.*$') {
    $text = [regex]::Replace($text, '(?mi)^[ \t]*Draft-hash[ \t]*:[^\r\n]*', $line, 1)
}
else {
    $m = [regex]::Match($text, '(?mi)^[ \t]*Status[ \t]*:[^\r\n]*')
    if (-not $m.Success) {
        Write-Error "No 'Status:' line in $Path. Only gate files get a draft hash."
        exit 1
    }
    $at = $m.Index + $m.Length
    $text = $text.Substring(0, $at) + $nl + $line + $text.Substring($at)
}

$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($full, $text, $enc)
Write-Output $line
