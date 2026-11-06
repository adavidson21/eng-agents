<#
.SYNOPSIS
  Makes one small edit to a product note in Workshop's Notes app: adds a line, replaces a line, or creates the note.

.DESCRIPTION
  The only way agents write product notes. It follows Notes' contract (adavidson21/notes README, "Tandem and
  product notes"):
    - writes only <Workshop data folder>/notes/products/<slug>.md and its snapshots in notes/history/;
    - keeps the current text as a snapshot (Notes' History panel can restore it) before every change;
    - writes atomically and starts again if the note changed while it worked;
    - sets tandem-changed in the frontmatter, so Notes shows "Changed by Tandem" until you mark it reviewed.

  One line per call. A line Tandem writes ends with its date and source: "- Exports are capped at 10k rows.
  (2026-11-05, PR 4812)". A line that says the same thing already is left alone. Checklist lines ("- [ ] ...")
  are refused: Notes would offer them to Docket.

.EXAMPLE
  Set-ProductNote.ps1 -Product "Wiki Edge" -Line "Exports are capped at 10k rows." -Source "PR 4812"
  Set-ProductNote.ps1 -Product wiki-edge -Section Gotchas -Replace "Exports are capped at 5k rows" -Line "Exports are capped at 10k rows." -Source "PR 4812"
  Set-ProductNote.ps1 -Product "Wiki Edge" -Create -Repos wiki-edge-api,wiki-edge-web -AlsoCalled "wiki","new wiki"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$Product,
    [string]$Section = "Remembered",
    [string]$Line,
    [string]$Source,
    [string]$Replace,
    [switch]$Create,
    [string]$Title,
    [string[]]$Repos,
    [string[]]$AlsoCalled
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "ProductNotes.ps1")

function Fail([string]$Message) { Write-Output "Not changed: $Message"; exit 1 }

$where = Get-ProductNotesHome
if (-not $where.Ok) { Fail "product notes are not available. $($where.Reason)" }

$slug = ConvertTo-NoteSlug $Product
$rel = "products/$slug.md"
$file = Join-Path $where.ProductsDir "$slug.md"
$now = [datetime]::UtcNow
$today = $now.ToString("yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
# -Repos a,b from -File arrives as one string: split on commas too.
$list = { param($items) "[" + ((@($items) | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ", ") + "]" }

# ---------------------------------------------------------------- create
if ($Create) {
    if (Test-Path -LiteralPath $file) {
        if (-not $Line) { Write-Output "Already there: $rel ($file)."; exit 0 }
    } else {
        $tplFile = Join-Path (Join-Path $where.NotesDir "templates") "product.md"
        $tpl = if (Test-Path -LiteralPath $tplFile -PathType Leaf) { Read-NoteText $tplFile } else { $script:BuiltInTemplate }
        $name = if ($Title) { $Title } else { $Product }
        $text = $tpl.Replace("{{title}}", $name).Replace("{{slug}}", $slug).Replace("{{date}}", $today).Replace("{{time}}", $now.ToLocalTime().ToString("HH:mm"))
        $n = Split-Note $text
        if ($Repos) { Set-NoteField $n "repos" (& $list $Repos) }
        if ($AlsoCalled) { Set-NoteField $n "also-called" (& $list $AlsoCalled) }
        Set-NoteField $n "tandem-changed" (Get-IsoNow $now)
        $out = Join-Note $n
        if (-not $out.EndsWith($n.Nl)) { $out += $n.Nl }
        Write-NoteAtomic $file $out
        Write-Output "Created $rel ($file) from $(if (Test-Path -LiteralPath $tplFile) { 'templates/product.md' } else { 'the built-in template' })."
        if (-not $Line) { exit 0 }
    }
}

# ---------------------------------------------------------------- one line
if (-not $Line) { Fail "give -Line (and -Source), or -Create." }
if (-not $Source) { Fail "give -Source: where you learned it (a PR, a work item, a file)." }
if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { Fail "$rel does not exist. Run with -Create first." }

$body = ($Line.Trim() -replace '^[-*]\s+', '').Trim()
if ($body -match '^\[[ xX]\]') { Fail "checklist lines (- [ ]) are not product facts." }
if ($body -match '[\r\n]') { Fail "one line only." }
$body = $body -replace '\s*\(\d{4}-\d{2}-\d{2}(,[^)]*)?\)\s*$', ''
$newLine = "- $body ($today, $($Source.Trim()))"
$norm = { param($s) (($s -replace '^\s*[-*]\s+', '') -replace '\s*\(\d{4}-\d{2}-\d{2}(,[^)]*)?\)\s*$', '').Trim().ToLowerInvariant() }

for ($attempt = 1; $attempt -le 3; $attempt++) {
    $stamp = (Get-Item -LiteralPath $file).LastWriteTimeUtc
    $before = Read-NoteText $file
    $n = Split-Note $before
    $lines = $n.Lines

    # Find the section: "## <Section>" in the body.
    $start = -1
    for ($i = $n.Front; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^##\s+(.+?)\s*#*\s*$' -and $Matches[1].Trim() -ieq $Section.Trim()) { $start = $i; break }
    }

    $old = $null
    if ($Replace) {
        $hits = @()
        for ($i = $n.Front; $i -lt $lines.Count; $i++) { if ($lines[$i].Contains($Replace)) { $hits += $i } }
        if ($hits.Count -eq 0) { Fail "no line contains `"$Replace`"." }
        if ($hits.Count -gt 1) { Fail "$($hits.Count) lines contain `"$Replace`". Give more of the line." }
        $old = $lines[$hits[0]]
        if ((& $norm $old) -eq (& $norm $newLine)) { Write-Output "Already there: $old"; exit 0 }
        $lines[$hits[0]] = $newLine
        $where_ = "line $($hits[0] + 1)"
    } else {
        for ($i = $n.Front; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*[-*]\s+' -and (& $norm $lines[$i]) -eq (& $norm $newLine)) { Write-Output "Already there: $($lines[$i])"; exit 0 }
        }
        if ($start -lt 0) {
            while ($lines.Count -gt 0 -and -not $lines[$lines.Count - 1].Trim()) { $lines.RemoveAt($lines.Count - 1) }
            $lines.Add(""); $lines.Add("## $Section"); $lines.Add(""); $lines.Add($newLine); $lines.Add("")
            $where_ = "new section ## $Section"
        } else {
            $end = $lines.Count
            for ($i = $start + 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^#{1,2}\s') { $end = $i; break } }
            $at = $end
            while ($at -gt $start + 1 -and -not $lines[$at - 1].Trim()) { $at-- }
            if ($at -eq $start + 1) { $lines.Insert($at, ""); $at++ }
            $lines.Insert($at, $newLine)
            if ($at + 1 -ge $lines.Count -or $lines[$at + 1].Trim()) { $lines.Insert($at + 1, "") }
            $where_ = "## $Section"
        }
    }

    Set-NoteField $n "tandem-changed" (Get-IsoNow $now)
    $after = Join-Note $n
    if (-not $after.EndsWith($n.Nl)) { $after += $n.Nl }

    if ((Get-Item -LiteralPath $file).LastWriteTimeUtc -ne $stamp) { Start-Sleep -Milliseconds 300; continue }
    $snap = Save-NoteSnapshot $where $rel $before $now
    if ((Get-Item -LiteralPath $file).LastWriteTimeUtc -ne $stamp) { Start-Sleep -Milliseconds 300; continue }
    Write-NoteAtomic $file $after

    Write-Output "Changed $rel ($where_)."
    if ($old) { Write-Output "Before: $old" }
    Write-Output "After:  $newLine"
    if ($snap) { Write-Output "Earlier version kept: notes/$snap (Notes, History)." }
    $count = ($after -split "\r?\n").Count
    if ($count -gt 150) { Write-Output "This note is $count lines (budget about 150). Propose a tidy to the engineer instead of adding more." }
    exit 0
}
Fail "$rel kept changing while I worked (open in Notes with unsaved edits?). Try again later."
