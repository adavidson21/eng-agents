<#
.SYNOPSIS
    Logs something an agent noticed that is out of scope for the current work, so it is not lost.

.DESCRIPTION
    Appends one line to <WorkRoot>\observations.md:

        - O<n> | <yyyy-mm-dd> | <kind> | <repo> | <source> | <text>

    Ids are never reused: the last one is kept in <WorkRoot>\.observation-ids.
    The same repo and text (case and spaces ignored) is not added twice: the script prints
    "DUPLICATE: O<n>" and changes nothing.

    The LAST line of output is the id (O<n>), or the DUPLICATE line.

    Workshop's Builds reads this file (its Inbox, Noticed). Builds keeps what you did with each
    line in its own state; this file is only ever appended to.

.EXAMPLE
    .\Add-Observation.ps1 -WorkRoot .work -Kind bug -Repo api -Source 12345 -Text "ExportJob swallows the timeout exception"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("bug", "debt", "docs", "tests", "idea")]
    [string]$Kind,

    [Parameter(Mandatory = $true)]
    [string]$Text,

    # The repo folder it is about, or "-" when it is not about one repo.
    [string]$Repo = "-",

    # The work item id or command that noticed it (for example 12345, L3, spike-auth).
    [string]$Source = "-",

    [string]$WorkRoot = ".work"
)

$ErrorActionPreference = "Stop"
$MaxText = 200

function Write-Utf8 {
    param([string]$Path, [string]$Content)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

# One cell: one line, no pipes, trimmed.
function Clean {
    param([string]$Value, [int]$Max = 100)
    $v = (($Value -replace "[\r\n]+", " ") -replace "\|", "/") -replace "\s+", " "
    $v = $v.Trim()
    if ($v.Length -gt $Max) { $v = $v.Substring(0, $Max - 3).TrimEnd() + "..." }
    if (-not $v) { $v = "-" }
    return $v
}

$Text = Clean $Text $MaxText
if ($Text -eq "-") { throw "Give the observation some text." }
$Repo = Clean $Repo
$Source = Clean $Source

if (-not (Test-Path -LiteralPath $WorkRoot)) { New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null }
$file = Join-Path $WorkRoot "observations.md"
$idsFile = Join-Path $WorkRoot ".observation-ids"

$header = "# Observations`n`nThings agents noticed that were out of scope. Added by Add-Observation.ps1 only; Workshop's Builds shows them in its Inbox. Never edit or reorder lines.`n`n"
$existing = if (Test-Path -LiteralPath $file) { [System.IO.File]::ReadAllText($file) } else { "" }

$norm = { param($s) (($s.ToLowerInvariant()) -replace "\s+", " ").Trim() }
$key = (& $norm $Repo) + "|" + (& $norm $Text)
$last = 0
foreach ($line in ($existing -split "\r?\n")) {
    $m = [regex]::Match($line, '^-\s+O(\d+)\s*\|\s*[^|]*\|\s*[^|]*\|\s*([^|]*)\|\s*[^|]*\|\s*(.*)$')
    if (-not $m.Success) { continue }
    $n = [int]$m.Groups[1].Value
    if ($n -gt $last) { $last = $n }
    if (((& $norm $m.Groups[2].Value) + "|" + (& $norm $m.Groups[3].Value)) -eq $key) {
        Write-Output "DUPLICATE: O$n"
        exit 0
    }
}

if (Test-Path -LiteralPath $idsFile) {
    $saved = 0
    if ([int]::TryParse(([System.IO.File]::ReadAllText($idsFile)).Trim(), [ref]$saved) -and $saved -gt $last) { $last = $saved }
}
$id = $last + 1

$date = (Get-Date).ToString("yyyy-MM-dd")
$entry = "- O$id | $date | $Kind | $Repo | $Source | $Text"
if (-not $existing) { $existing = $header }
elseif (-not $existing.EndsWith("`n")) { $existing += "`n" }
Write-Utf8 $file ($existing + $entry + "`n")
Write-Utf8 $idsFile "$id"

Write-Output "O$id"
