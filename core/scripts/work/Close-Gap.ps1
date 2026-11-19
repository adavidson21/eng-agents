<#
.SYNOPSIS
    Closes a knowledge gap in <WorkRoot>\gaps.md once its answer is written where it belongs.

.DESCRIPTION
    Changes the last cell of the G<n> line from "open" to "answered <yyyy-mm-dd>: <where>", where <where>
    says where the answer now lives (for example "products/sample-portal.md, Rules" or
    "portal-api repo guide, Remembered"). Nothing else in the file changes.

    The LAST line of output is "CLOSED: G<n>", "ALREADY: G<n>" (it was closed before) or "NOT FOUND: G<n>".

.EXAMPLE
    .\Close-Gap.ps1 -WorkRoot .work -Id G3 -Where "products/sample-portal.md, Rules"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^G\d+$')]
    [string]$Id,

    [Parameter(Mandatory = $true)]
    [string]$Where,

    [string]$WorkRoot = ".work"
)

$ErrorActionPreference = "Stop"
$file = Join-Path $WorkRoot "gaps.md"
if (-not (Test-Path -LiteralPath $file)) { Write-Output "NOT FOUND: $Id"; exit 1 }

$w = ((($Where -replace "[\r\n]+", " ") -replace "\|", "/") -replace "\s+", " ").Trim()
if ($w.Length -gt 120) { $w = $w.Substring(0, 117).TrimEnd() + "..." }
if (-not $w) { throw "Say where the answer was written." }

$text = [System.IO.File]::ReadAllText($file)
$nl = if ($text -match "\r\n") { "`r`n" } else { "`n" }
$lines = $text -split "\r?\n"
$found = $false
for ($i = 0; $i -lt $lines.Count; $i++) {
    $m = [regex]::Match($lines[$i], "^(-\s+$Id\s*\|.*\|)\s*([^|]*)$")
    if (-not $m.Success) { continue }
    $found = $true
    if ($m.Groups[2].Value.Trim() -ne "open") { Write-Output "ALREADY: $Id"; exit 0 }
    $lines[$i] = $m.Groups[1].Value + " answered " + (Get-Date).ToString("yyyy-MM-dd") + ": " + $w
    break
}
if (-not $found) { Write-Output "NOT FOUND: $Id"; exit 1 }
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($file, ($lines -join $nl), $enc)
Write-Output "CLOSED: $Id"
