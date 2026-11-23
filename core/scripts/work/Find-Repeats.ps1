<#
.SYNOPSIS
    The automatic run retro: finds what keeps coming back across work items and suggests a fix once, in
    Notes' review list, for the engineer to accept or dismiss. Run by /pr at the end of every build.

.DESCRIPTION
    Two kinds of repeat, each suggested once (the keys already suggested are kept in <WorkRoot>\.repeats):
      - A review finding with the same repo and category in 3 or more work items (Get-ReviewFindings.ps1).
        Suggests a /memory rule for that repo.
      - The same knowledge gap kind and product in 3 or more gaps (gaps.md). Suggests filling that part of
        the product note or the handbook up front.

    With -Write, each new suggestion is added to Notes' tandem/changes.md with Set-ProductNote.ps1
    (so it shows in Notes' review list) and its key is saved. Without -Write it only prints them.
    It never blocks: when product notes are not available it prints the suggestions and saves nothing.

    The LAST line of output is "REPEATS: <n> new" (n may be 0).

.EXAMPLE
    .\Find-Repeats.ps1 -WorkRoot .work -Write
#>
[CmdletBinding()]
param(
    [string]$WorkRoot = ".work",
    [int]$Threshold = 3,
    [switch]$Write
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $WorkRoot -PathType Container)) { Write-Output "REPEATS: 0 new"; exit 0 }

$exe = (Get-Process -Id $PID).Path
$keysFile = Join-Path $WorkRoot ".repeats"
$done = @{}
if (Test-Path -LiteralPath $keysFile) { foreach ($k in [IO.File]::ReadAllLines($keysFile)) { if ($k.Trim()) { $done[$k.Trim()] = $true } } }

$suggestions = New-Object System.Collections.ArrayList

# Review findings: same repo and category in Threshold+ items.
$findScript = Join-Path $PSScriptRoot "..\stats\Get-ReviewFindings.ps1"
try {
    $json = & $exe -NoProfile -ExecutionPolicy Bypass -File $findScript -WorkRoot $WorkRoot -AsJson 2>$null | Out-String
    $data = $json | ConvertFrom-Json
    foreach ($p in @($data.patterns)) {
        if (-not $p -or [int]$p.itemCount -lt $Threshold) { continue }
        $key = "finding|$($p.repo)|$($p.category)".ToLowerInvariant()
        if ($done.ContainsKey($key)) { continue }
        $items = (@($p.items) | Select-Object -First 5) -join ", "
        [void]$suggestions.Add(@{ key = $key; line = "Suggestion: reviews keep finding $($p.category) problems in $($p.repo) ($($p.itemCount) items: $items). Add a /memory rule for $($p.repo) so the implementer gets it right first time?" })
    }
} catch {
    Write-Output "Could not read review findings: $($_.Exception.Message)"
}

# Knowledge gaps: same kind and product in Threshold+ gaps.
$gapsFile = Join-Path $WorkRoot "gaps.md"
if (Test-Path -LiteralPath $gapsFile) {
    $counts = @{}
    foreach ($line in [IO.File]::ReadAllLines($gapsFile)) {
        $m = [regex]::Match($line, '^-\s+G\d+\s*\|\s*[^|]*\|\s*([^|]*?)\s*\|\s*([^|]*?)\s*\|')
        if (-not $m.Success) { continue }
        $k = "$($m.Groups[1].Value)|$($m.Groups[2].Value)"
        $counts[$k] = 1 + [int]$counts[$k]
    }
    foreach ($k in $counts.Keys) {
        if ($counts[$k] -lt $Threshold) { continue }
        $kind, $product = $k -split '\|', 2
        $key = "gap|$k".ToLowerInvariant()
        if ($done.ContainsKey($key)) { continue }
        $where = if ($kind -eq 'process') { "the team handbook" } elseif ($product -and $product -ne '-') { "the $product note" } else { "the product notes" }
        [void]$suggestions.Add(@{ key = $key; line = "Suggestion: agents asked $($counts[$k]) $kind questions about $(if ($product -and $product -ne '-') { $product } else { 'no product in particular' }). Fill in $where up front (Settings, Knowledge, Draft from sources) so builds stop asking?" })
    }
}

$new = 0
$setNote = Join-Path $PSScriptRoot "..\notes\Set-ProductNote.ps1"
foreach ($s in $suggestions) {
    Write-Output $s.line
    if (-not $Write) { continue }
    $r = & $exe -NoProfile -ExecutionPolicy Bypass -File $setNote -Note "tandem/changes.md" -Line $s.line -Source "run retro" 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Write-Output "Not saved (product notes not available?): $(($r.Trim() -split "\r?\n")[-1])"; continue }
    Add-Content -LiteralPath $keysFile -Value $s.key -Encoding utf8
    $new++
}
if (-not $Write) { $new = $suggestions.Count }
Write-Output "REPEATS: $new new"
