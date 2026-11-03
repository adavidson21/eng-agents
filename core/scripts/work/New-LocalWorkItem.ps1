<#
.SYNOPSIS
    Creates a work item folder for work that has no tracker item (no ADO, no GitHub issue).

.DESCRIPTION
    Gives the work a local id, L<number> (L1, L2, ...), and creates
    <WorkRoot>\L<number>-<short-name>\workitem.md from the title and description.
    Numbers are never reused, even after a folder is removed: the last one is kept in
    <WorkRoot>\.local-ids.

    The LAST line of output is always the folder path, so the calling agent can use it.

    Dispatch (Workshop's opencode connector) creates the same folder and file itself when
    you use Start a work item > Describe it. Keep the two formats the same.

.EXAMPLE
    .\New-LocalWorkItem.ps1 -WorkRoot .work -Title "Export job fails on retry" -Type Bug

.EXAMPLE
    .\New-LocalWorkItem.ps1 -WorkRoot .work -Title "Add CSV export" -DescriptionFile notes.txt
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Title,

    [string]$WorkRoot = ".work",

    [ValidateSet("Feature", "Bug")]
    [string]$Type = "Feature",

    # The description as text, or a file holding it. Leave both out to fill it in later.
    [string]$Description,
    [string]$DescriptionFile,

    # Acceptance criteria as text. Leave out for "None provided". Export-Backlog.ps1 -Local passes the story's scenarios.
    [string]$AcceptanceCriteria
)

$ErrorActionPreference = "Stop"

function ConvertTo-Slug {
    param([string]$Text)
    $stop = @("a", "an", "the", "to", "of", "for", "and", "or", "in", "on", "at", "with", "is", "be", "when", "from", "by")
    $words = ($Text.ToLowerInvariant() -replace "[^a-z0-9 ]", " ") -split "\s+" |
        Where-Object { $_ -and ($stop -notcontains $_) }
    $slug = (@($words) | Select-Object -First 5) -join "-"
    if ($slug.Length -gt 40) { $slug = $slug.Substring(0, 40).TrimEnd("-") }
    if (-not $slug) { $slug = "item" }
    return $slug
}

function Write-Utf8 {
    param([string]$Path, [string]$Content)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

$Title = ($Title -replace "[\r\n]+", " ").Trim()
if (-not $Title) { throw "Give the work a title." }
if (-not (Test-Path $WorkRoot)) { New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null }

# Next local number: one more than the highest in .local-ids or in any L<number>- folder.
$counterFile = Join-Path $WorkRoot ".local-ids"
$max = 0
if (Test-Path $counterFile) {
    $t = ([System.IO.File]::ReadAllText($counterFile)).Trim()
    if ($t -match '^\d+$') { $max = [int]$t }
}
foreach ($d in @(Get-ChildItem -LiteralPath $WorkRoot -Directory -ErrorAction SilentlyContinue)) {
    if ($d.Name -match '^L(\d+)-') { $n = [int]$Matches[1]; if ($n -gt $max) { $max = $n } }
}
$id = "L$($max + 1)"
Write-Utf8 $counterFile "$($max + 1)`n"

$folder = Join-Path $WorkRoot "$id-$(ConvertTo-Slug $Title)"
New-Item -ItemType Directory -Path $folder -Force | Out-Null

$desc = $Description
if ($DescriptionFile) { $desc = [System.IO.File]::ReadAllText((Resolve-Path $DescriptionFile).Path) }
$desc = "$desc".Trim()
if (-not $desc) { $desc = "<describe the work here>" }
$criteria = "$AcceptanceCriteria".Trim()
if (-not $criteria) { $criteria = "None provided" }
$repro = $(if ($Type -eq "Bug") { "<steps to reproduce, or ""See the description"">" } else { "Not a bug" })
$today = (Get-Date).ToString("yyyy-MM-dd")

$md = @"
# Work item ${id}: $Title

- Type: $Type
- Source: Local (no tracker item)
- Created: $today

## Description

$desc

## Acceptance criteria

$criteria

## Repro steps (bugs only)

$repro

## Extra context from the engineer

None
"@
Write-Utf8 (Join-Path $folder "workitem.md") $md
Write-Output "Created local work item $id."
Write-Output (Resolve-Path $folder).Path
