<#
.SYNOPSIS
  Makes one small edit to a product note, the team handbook or Tandem's change log in Workshop's Notes app: adds a
  line, replaces a line, flags a line, or creates the note.

.DESCRIPTION
  The only way agents write these notes. It follows Notes' contract (Workshop apps/notes/README.md, "Tandem and
  product notes"):
    - writes only <Workshop data folder>/notes/products/<slug>.md, notes/team/handbook.md, notes/tandem/changes.md
      and their snapshots in notes/history/ (folio/ instead of notes/ with a Workshop that has not renamed the folder);
    - keeps the current text as a snapshot (Notes' History panel can restore it) before every change;
    - writes atomically and starts again if the note changed while it worked;
    - sets tandem-changed in the frontmatter, so Notes shows "Changed by Tandem" until you mark it reviewed.

  One line per call. A line Tandem writes ends with its date and source: "- Exports are capped at 10k rows.
  (2026-11-05, PR 4812)". A line that says the same thing already is left alone. Checklist lines ("- [ ] ...")
  are refused: Notes would offer them to Tasks. -Flag marks a line the code contradicts when the right value is
  not confirmed: "(check: <reason>, <date>, <source>)" goes at its end and Notes shows the note as stale.
  The team handbook and the change log are made from built-in templates the first time a line goes in.

.EXAMPLE
  Set-ProductNote.ps1 -Product "Wiki Edge" -Line "Exports are capped at 10k rows." -Source "PR 4812"
  Set-ProductNote.ps1 -Product wiki-edge -Section Gotchas -Replace "Exports are capped at 5k rows" -Line "Exports are capped at 10k rows." -Source "PR 4812"
  Set-ProductNote.ps1 -Product "Wiki Edge" -Flag "Exports are capped at 5k rows" -Reason "ExportService uses 10000" -Source "src/ExportService.cs"
  Set-ProductNote.ps1 -Note team/handbook.md -Section "Pull requests" -Line "Two approvals before merge." -Source "the engineer"
  Set-ProductNote.ps1 -Note tandem/changes.md -Line "api-repo repo guide, Remembered: added Run tests with --no-build." -Source "/memory"
  Set-ProductNote.ps1 -Product "Wiki Edge" -Create -Repos wiki-edge-api,wiki-edge-web -AlsoCalled "wiki","new wiki"
#>
[CmdletBinding()]
param(
    [string]$Product,
    [string]$Note,
    [string]$Section,
    [string]$Line,
    [string]$Source,
    [string]$Replace,
    [string]$Flag,
    [string]$Reason,
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

if ($Note) {
    $rel = Resolve-KnowledgeNote $Note
    if (-not $rel) { Fail "-Note must be products/<name>.md, team/handbook.md or tandem/changes.md." }
    $slug = if ($rel -like "products/*") { $rel.Substring(9, $rel.Length - 12) } else { $null }
} elseif ($Product) {
    $slug = ConvertTo-NoteSlug $Product
    $rel = "products/$slug.md"
} else { Fail "give -Product or -Note." }
$shared = ($rel -eq $script:HandbookPath -or $rel -eq $script:ChangesPath)
if (-not $Section) { $Section = if ($rel -eq $script:ChangesPath) { "Changes" } else { "Remembered" } }
$file = Join-Path $where.NotesDir ($rel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
$now = [datetime]::UtcNow
$today = $now.ToString("yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
# -Repos a,b from -File arrives as one string: split on commas too.
$list = { param($items) "[" + ((@($items) | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ", ") + "]" }

# The handbook and the change log are made the first time something goes in.
if ($shared -and ($Line -or $Flag) -and -not (Test-Path -LiteralPath $file -PathType Leaf)) {
    $tpl = if ($rel -eq $script:HandbookPath) { $script:BuiltInHandbook } else { $script:BuiltInChanges }
    Write-NoteAtomic $file $tpl
    Write-Output "Created $rel ($file) from the built-in template."
}

# ---------------------------------------------------------------- flag a line
if ($Flag) {
    if (-not $Reason) { Fail "give -Reason: what the code says instead." }
    if (-not $Source) { Fail "give -Source: where you saw it (a file, a PR, a work item)." }
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { Fail "$rel does not exist." }
    $clean = { param($t) (($t -replace '[()\r\n]+', ' ') -replace '\s+', ' ').Trim() }
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $stamp = (Get-Item -LiteralPath $file).LastWriteTimeUtc
        $before = Read-NoteText $file
        $n = Split-Note $before
        $hits = @()
        for ($i = $n.Front; $i -lt $n.Lines.Count; $i++) { if ($n.Lines[$i].Contains($Flag)) { $hits += $i } }
        if ($hits.Count -eq 0) { Fail "no line contains `"$Flag`"." }
        if ($hits.Count -gt 1) { Fail "$($hits.Count) lines contain `"$Flag`". Give more of the line." }
        $old = $n.Lines[$hits[0]]
        if ($old -match '\(check:[^)]*\)\s*$') { Write-Output "Already flagged: $old"; exit 0 }
        $n.Lines[$hits[0]] = "$($old.TrimEnd()) (check: $(& $clean $Reason), $today, $(& $clean $Source))"
        Set-NoteField $n "tandem-changed" (Get-IsoNow $now)
        $after = Join-Note $n
        if (-not $after.EndsWith($n.Nl)) { $after += $n.Nl }
        if ((Get-Item -LiteralPath $file).LastWriteTimeUtc -ne $stamp) { Start-Sleep -Milliseconds 300; continue }
        $snap = Save-NoteSnapshot $where $rel $before $now
        if ((Get-Item -LiteralPath $file).LastWriteTimeUtc -ne $stamp) { Start-Sleep -Milliseconds 300; continue }
        Write-NoteAtomic $file $after
        Write-Output "Flagged in $rel."
        Write-Output "Before: $old"
        Write-Output "After:  $($n.Lines[$hits[0]])"
        if ($snap) { Write-Output "Earlier version kept: $($where.Folder)/$snap (Notes, History)." }
        exit 0
    }
    Fail "$rel kept changing while I worked (open in Notes with unsaved edits?). Try again later."
}

# ---------------------------------------------------------------- create
if ($Create) {
    if (-not $slug) { Fail "-Create is for product notes; the handbook and the change log are made by themselves." }
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
if (-not $Line) { Fail "give -Line (and -Source), -Flag (with -Reason and -Source), or -Create." }
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

    # The change log keeps its newest lines only; the older ones stay in its snapshots.
    $dropped = 0
    if ($rel -eq $script:ChangesPath) {
        $bullets = @(for ($i = $n.Front; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*[-*]\s+') { $i } })
        $dropped = [Math]::Max(0, $bullets.Count - $script:ChangesKeep)
        for ($k = $dropped - 1; $k -ge 0; $k--) { $lines.RemoveAt($bullets[$k]) }
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
    if ($snap) { Write-Output "Earlier version kept: $($where.Folder)/$snap (Notes, History)." }
    if ($dropped) { Write-Output "Dropped the $dropped oldest change lines (the log keeps $($script:ChangesKeep))." }
    $count = ($after -split "\r?\n").Count
    if ($rel -ne $script:ChangesPath -and $count -gt 150) { Write-Output "This note is $count lines (budget about 150). Propose a tidy to the engineer instead of adding more." }
    exit 0
}
Fail "$rel kept changing while I worked (open in Notes with unsaved edits?). Try again later."
