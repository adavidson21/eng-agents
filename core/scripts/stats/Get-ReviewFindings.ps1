<#
.SYNOPSIS
    Every review finding across .work, grouped to show mistakes that repeat. Used by /retro.

.DESCRIPTION
    Read-only and local. For each work item folder (.work\<id>-<name>\) it reads review.md and every
    earlier round in history\review-*.md, and takes each row of the findings table:
      | # | Severity | Category | Location | Problem | Suggested fix |     (Core 2.23.0+)
      | # | Severity | Location | Problem | Suggested fix |                (older: category "uncategorized")
    The repo is the first folder of the Location (`api/src/File.cs:12` -> api).

    A pattern is one repo and one category. It repeats when it shows up in 2 or more work items
    (several rounds of one item count once). Patterns are listed most items first.

    With -Id it reads only that work item, and every finding counts as its own row (no repeat filter).
    With -AsJson it prints one line of JSON (schema version 1) and nothing else.

.EXAMPLE
    .\Get-ReviewFindings.ps1 -WorkRoot .work -Since 2026-11-01

.EXAMPLE
    .\Get-ReviewFindings.ps1 -WorkRoot .work -Id 12345 -AsJson
#>
[CmdletBinding()]
param(
    [string]$WorkRoot = ".work",
    # Only reviews written on or after this date (yyyy-MM-dd), by file date.
    [string]$Since,
    # Only this work item (ADO id or local L id).
    [string]$Id,
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSVersion.Major -lt 6) { Remove-TypeData System.Array -ErrorAction SilentlyContinue }

if (-not (Test-Path -LiteralPath $WorkRoot -PathType Container)) { Write-Error "No .work folder at $WorkRoot"; exit 1 }
$sinceDate = $null
if ($Since) {
    $d = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($Since, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$d)) { Write-Error "-Since must be yyyy-MM-dd"; exit 1 }
    $sinceDate = $d
}

function Get-Cells([string]$Line) {
    $t = $Line.Trim()
    if (-not $t.StartsWith("|")) { return $null }
    $parts = $t.Trim("|").Split("|")
    return , @($parts | ForEach-Object { $_.Trim().Trim('`').Trim() })
}

$findings = New-Object System.Collections.ArrayList
$reviewed = New-Object System.Collections.ArrayList
foreach ($dir in (Get-ChildItem -LiteralPath $WorkRoot -Directory | Sort-Object Name)) {
    $nm = [regex]::Match($dir.Name, '^(\d+|L\d+)-(.+)$')
    if (-not $nm.Success) { continue }
    if ($Id -and $nm.Groups[1].Value -ne $Id) { continue }

    $files = @()
    $hist = Join-Path $dir.FullName "history"
    if (Test-Path -LiteralPath $hist) { $files += @(Get-ChildItem -LiteralPath $hist -Filter "review-*.md" -File | Sort-Object Name) }
    $cur = Join-Path $dir.FullName "review.md"
    if (Test-Path -LiteralPath $cur) { $files += Get-Item -LiteralPath $cur }
    $any = $false
    foreach ($f in $files) {
        if ($sinceDate -and $f.LastWriteTime.Date -lt $sinceDate) { continue }
        $any = $true
        foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
            $c = Get-Cells $line
            if (-not $c -or $c.Count -lt 5) { continue }
            if ($c[0] -notmatch '^\d+$') { continue }
            if ($c[1] -notmatch '^(Blocker|Should fix|Nit)$') { continue }
            if ($c.Count -ge 6) { $cat = $c[2].ToLowerInvariant(); $loc = $c[3]; $prob = $c[4] }
            else { $cat = "uncategorized"; $loc = $c[2]; $prob = $c[3] }
            if (-not $cat -or $cat -match '^<.*>$') { $cat = "uncategorized" }
            $repo = $null
            $rm = [regex]::Match($loc, '^([^/\\:\s]+)[/\\]')
            if ($rm.Success) { $repo = $rm.Groups[1].Value }
            [void]$findings.Add([ordered]@{
                id = $nm.Groups[1].Value; item = $dir.Name; file = $(if ($f.Name -eq "review.md") { "review.md" } else { "history/" + $f.Name })
                severity = $c[1]; category = $cat; repo = $repo; location = $loc; problem = $prob
            })
        }
    }
    if ($any) { [void]$reviewed.Add($dir.Name) }
}

# Patterns: repo + category across distinct items.
$groups = [ordered]@{}
foreach ($f in $findings) {
    $key = "$(if ($f.repo) { $f.repo } else { '(no repo)' })|$($f.category)"
    if (-not $groups.Contains($key)) { $groups[$key] = [ordered]@{ repo = $f.repo; category = $f.category; items = New-Object System.Collections.ArrayList; findings = 0; blockers = 0; examples = New-Object System.Collections.ArrayList } }
    $g = $groups[$key]
    if (-not $g.items.Contains($f.item)) { [void]$g.items.Add($f.item) }
    $g.findings++
    if ($f.severity -eq "Blocker") { $g.blockers++ }
    if ($g.examples.Count -lt 3) { [void]$g.examples.Add("$($f.item): $($f.problem)") }
}
$patterns = @($groups.Values | ForEach-Object {
        [ordered]@{ repo = $_.repo; category = $_.category; itemCount = $_.items.Count; items = @($_.items); findings = $_.findings; blockers = $_.blockers; repeats = ($_.items.Count -ge 2); examples = @($_.examples) }
    } | Sort-Object -Property @{ Expression = { $_.itemCount }; Descending = $true }, @{ Expression = { $_.findings }; Descending = $true })

$result = [ordered]@{
    version         = 1
    since           = $(if ($sinceDate) { $sinceDate.ToString("yyyy-MM-dd") } else { $null })
    itemsReviewed   = $reviewed.Count
    findings        = @($findings)
    patterns        = $patterns
}

if ($AsJson) {
    $json = $result | ConvertTo-Json -Depth 6 -Compress
    $json = [regex]::Replace($json, '[^\x00-\x7F]', { param($m) '\u{0:x4}' -f [int][char]$m.Value })
    Write-Output $json
    exit 0
}

$out = New-Object System.Collections.Generic.List[string]
$out.Add("# Review findings")
$out.Add("")
$out.Add("$($findings.Count) findings in $($reviewed.Count) reviewed work items$(if ($sinceDate) { " since $($sinceDate.ToString('yyyy-MM-dd'))" }).")
$out.Add("")
$rep = @($patterns | Where-Object { $_.repeats })
if (-not $Id) {
    $out.Add("## Repeating patterns (same repo and category in 2+ items)")
    $out.Add("")
    if ($rep.Count -eq 0) { $out.Add("None yet.") }
    else {
        $out.Add("| Repo | Category | Items | Findings | Blockers | Examples |")
        $out.Add("|---|---|---|---|---|---|")
        foreach ($p in $rep) { $out.Add("| $(if ($p.repo) { $p.repo } else { 'n/a' }) | $($p.category) | $($p.itemCount) | $($p.findings) | $($p.blockers) | $(($p.examples -join '; ') -replace '\|', '/') |") }
    }
    $out.Add("")
}
$out.Add("## All findings")
$out.Add("")
if ($findings.Count -eq 0) { $out.Add("None.") }
else {
    $out.Add("| Item | Round | Severity | Category | Location | Problem |")
    $out.Add("|---|---|---|---|---|---|")
    foreach ($f in $findings) { $out.Add("| $($f.item) | $($f.file) | $($f.severity) | $($f.category) | ``$($f.location)`` | $($f.problem -replace '\|', '/') |") }
}
$out | ForEach-Object { Write-Output $_ }
