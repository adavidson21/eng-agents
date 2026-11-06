<#
.SYNOPSIS
  Prints a product note from Workshop's Notes app, or lists them all.

.DESCRIPTION
  Product notes are one Markdown file per product in <Workshop data folder>/notes/products/<slug>.md.
  They hold what the code cannot tell you: business rules, gotchas, who to ask, decisions. Read-only.

  If product notes are not available (Workshop not installed, Notes switched off), it prints why and exits 0,
  so callers can go on without them.

.EXAMPLE
  Get-ProductNote.ps1 -Product "Wiki Edge"
  Get-ProductNote.ps1 -Product wiki-edge -Path
  Get-ProductNote.ps1 -List
#>
[CmdletBinding(DefaultParameterSetName = "One")]
param(
    [Parameter(ParameterSetName = "One", Mandatory = $true, Position = 0)] [string]$Product,
    [Parameter(ParameterSetName = "One")] [string]$Note,
    [Parameter(ParameterSetName = "One")] [switch]$Path,
    [Parameter(ParameterSetName = "List", Mandatory = $true)] [switch]$List
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "ProductNotes.ps1")

$where = Get-ProductNotesHome
if (-not $where.Ok) {
    Write-Output "Product notes: not available. $($where.Reason)"
    exit 0
}

if ($List) {
    Write-Output "Product notes: $($where.ProductsDir)"
    if (-not (Test-Path -LiteralPath $where.ProductsDir)) { Write-Output "(none yet)"; exit 0 }
    $files = @(Get-ChildItem -LiteralPath $where.ProductsDir -Filter *.md -File | Where-Object { $_.Name -match '^[a-z0-9][a-z0-9-]{0,39}\.md$' } | Sort-Object Name)
    if (-not $files.Count) { Write-Output "(none yet)"; exit 0 }
    foreach ($f in $files) {
        $n = Split-Note (Read-NoteText $f.FullName)
        $title = $f.BaseName; $changed = ""; $reviewed = ""
        for ($i = 1; $i -lt $n.Front - 1; $i++) {
            if ($n.Lines[$i] -match '^title\s*:\s*(.+)$') { $title = $Matches[1].Trim().Trim('"', "'") }
            elseif ($n.Lines[$i] -match '^tandem-changed\s*:\s*(.*)$') { $changed = $Matches[1].Trim() }
            elseif ($n.Lines[$i] -match '^reviewed\s*:\s*(.*)$') { $reviewed = $Matches[1].Trim() }
        }
        $flag = ""
        if ($changed -and (-not $reviewed -or [string]::CompareOrdinal($changed, $reviewed) -gt 0)) { $flag = "  (changed by Tandem, not reviewed yet)" }
        Write-Output "- products/$($f.Name)  $title$flag"
    }
    exit 0
}

$slug = if ($Note) { ConvertTo-NoteSlug ($Note -replace '^products/', '' -replace '\.md$', '') } else { ConvertTo-NoteSlug $Product }
$file = Join-Path $where.ProductsDir "$slug.md"
if ($Path) { Write-Output $file; exit 0 }
if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
    Write-Output "Product note: products/$slug.md does not exist yet ($file)."
    exit 0
}
Write-Output "Product note: products/$slug.md ($file)"
Write-Output ""
Write-Output (Read-NoteText $file)
