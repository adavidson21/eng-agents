<#
.SYNOPSIS
    Logs knowledge an agent was missing (a business rule, a term, which repo or process applies), so the
    engineer answers it once in Workshop instead of being asked in the middle of a build.

.DESCRIPTION
    Appends one line to <WorkRoot>\gaps.md:

        - G<n> | <yyyy-mm-dd> | <kind> | <product> | <source> | <question> | <assumed> | open

    <assumed> is what the agent did instead, or "-" when it had no safe assumption and stopped.
    Ids are never reused: the last one is kept in <WorkRoot>\.gap-ids.
    The same product and question (case and spaces ignored) is not added twice: the script prints
    "DUPLICATE: G<n>" and changes nothing.

    The LAST line of output is the id (G<n>), or the DUPLICATE line.

    Workshop's Loom and Docket show open gaps as Teach cards. Answering one runs /teach, which writes the
    answer where it belongs and closes the gap with Close-Gap.ps1. Only these two scripts write gaps.md.

.EXAMPLE
    .\Add-Gap.ps1 -WorkRoot .work -Kind fact -Product "Sample Portal" -Source L12 -Question "May a refund exceed the order total?" -Assumed "No, capped at the order total"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("fact", "term", "repo", "process")]
    [string]$Kind,

    [Parameter(Mandatory = $true)]
    [string]$Question,

    # What the agent did instead, or "-" when there was no safe assumption.
    [string]$Assumed = "-",

    # The product it is about (as in the repo map), or "-".
    [string]$Product = "-",

    # The work item id or command that hit the gap (for example 12345, L3, /spec).
    [string]$Source = "-",

    [string]$WorkRoot = ".work"
)

$ErrorActionPreference = "Stop"

function Write-Utf8 {
    param([string]$Path, [string]$Content)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

function Clean {
    param([string]$Value, [int]$Max = 100)
    $v = (($Value -replace "[\r\n]+", " ") -replace "\|", "/") -replace "\s+", " "
    $v = $v.Trim()
    if ($v.Length -gt $Max) { $v = $v.Substring(0, $Max - 3).TrimEnd() + "..." }
    if (-not $v) { $v = "-" }
    return $v
}

$Question = Clean $Question 200
if ($Question -eq "-") { throw "Give the gap a question." }
$Assumed = Clean $Assumed 200
$Product = Clean $Product
$Source = Clean $Source

if (-not (Test-Path -LiteralPath $WorkRoot)) { New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null }
$file = Join-Path $WorkRoot "gaps.md"
$idsFile = Join-Path $WorkRoot ".gap-ids"

$header = "# Knowledge gaps`n`nWhat agents needed to know and could not find. Added by Add-Gap.ps1, closed by Close-Gap.ps1; Workshop shows open ones as Teach cards. Never edit lines by hand.`n`n"
$existing = if (Test-Path -LiteralPath $file) { [System.IO.File]::ReadAllText($file) } else { "" }

$norm = { param($s) (($s.ToLowerInvariant()) -replace "\s+", " ").Trim() }
$key = (& $norm $Product) + "|" + (& $norm $Question)
$last = 0
foreach ($line in ($existing -split "\r?\n")) {
    $m = [regex]::Match($line, '^-\s+G(\d+)\s*\|\s*[^|]*\|\s*[^|]*\|\s*([^|]*)\|\s*[^|]*\|\s*([^|]*)\|')
    if (-not $m.Success) { continue }
    $n = [int]$m.Groups[1].Value
    if ($n -gt $last) { $last = $n }
    if (((& $norm $m.Groups[2].Value) + "|" + (& $norm $m.Groups[3].Value)) -eq $key) {
        Write-Output "DUPLICATE: G$n"
        exit 0
    }
}

if (Test-Path -LiteralPath $idsFile) {
    $saved = 0
    if ([int]::TryParse(([System.IO.File]::ReadAllText($idsFile)).Trim(), [ref]$saved) -and $saved -gt $last) { $last = $saved }
}
$id = $last + 1

$date = (Get-Date).ToString("yyyy-MM-dd")
$entry = "- G$id | $date | $Kind | $Product | $Source | $Question | $Assumed | open"
if (-not $existing) { $existing = $header }
elseif (-not $existing.EndsWith("`n")) { $existing += "`n" }
Write-Utf8 $file ($existing + $entry + "`n")
Write-Utf8 $idsFile "$id"

Write-Output "G$id"
