<#
.SYNOPSIS
    Pipeline health across every work item in .work: where time and rework go, and which gates you
    edit versus approve as written. Used by /stats and by Workshop's Dispatch Health tab.

.DESCRIPTION
    Read-only and local: it reads .work and makes no network calls.

    What it reads, for each .work\<id>-<name>\ folder (ADO ids and local L ids):
      repos.md     lane and repo count
      progress.md  entry dates per command, the "Verify:" line, and the "Stats:" line
                   (key=value pairs, Core 2.22.0+; older entries simply have none)
      tasks.md     tasks planned, done, and added after /tasks
      review.md    verdict and Pass 2 findings by severity
    Scope, spike, triage, shape, refine, docs, TSD and pr-<id> folders are skipped: they are not work items.

    Missing data is reported as null (shown as n/a), never guessed.

    With -AsJson it prints one line of JSON (schema version 1) and nothing else.

.EXAMPLE
    .\Get-PipelineStats.ps1 -WorkRoot .work

.EXAMPLE
    .\Get-PipelineStats.ps1 -WorkRoot C:\src\work\.work -Since 2026-11-01 -AsJson
#>
[CmdletBinding()]
param(
    [string]$WorkRoot = ".work",
    # Only items whose /start (or first entry) is on or after this date, yyyy-MM-dd.
    [string]$Since,
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSVersion.Major -lt 6) { Remove-TypeData System.Array -ErrorAction SilentlyContinue }

$SchemaVersion = 1
$inv = [System.Globalization.CultureInfo]::InvariantCulture

# ------------------------------------------------------------------- helpers

function Read-Text {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return [System.IO.File]::ReadAllText($Path)
}

function ConvertTo-Date {
    param([string]$Value)
    $d = [datetime]::MinValue
    if ([datetime]::TryParseExact($Value, "yyyy-MM-dd", $inv, [System.Globalization.DateTimeStyles]::None, [ref]$d)) { return $d }
    return $null
}

function Get-Median {
    param([double[]]$Values)
    $v = @($Values | Sort-Object)
    if ($v.Count -eq 0) { return $null }
    $mid = [math]::Floor($v.Count / 2)
    if ($v.Count % 2 -eq 1) { return [math]::Round($v[$mid], 1) }
    return [math]::Round(($v[$mid - 1] + $v[$mid]) / 2, 1)
}

function Get-Rate {
    param([int]$Part, [int]$Whole)
    if ($Whole -le 0) { return $null }
    return [math]::Round(100.0 * $Part / $Whole)
}

# progress.md entries: date, command, verify, and the Stats key=value pairs.
function Get-Entries {
    param([string]$Text)
    $list = New-Object System.Collections.ArrayList
    if (-not $Text) { return , @() }
    $cur = $null
    foreach ($line in ($Text -split "\r?\n")) {
        $m = [regex]::Match($line, '^##\s+(\d{4}-\d{2}-\d{2})[^|]*\|\s*`?/?([A-Za-z][\w-]*)')
        if ($m.Success) {
            $cur = [ordered]@{ date = (ConvertTo-Date $m.Groups[1].Value); command = $m.Groups[2].Value.ToLowerInvariant(); verify = $null; stats = @{} }
            [void]$list.Add($cur)
            continue
        }
        if ($line -match '^##\s') { $cur = $null; continue }
        if (-not $cur) { continue }
        $v = [regex]::Match($line, '^\s*-\s*Verify\s*:.*?->\s*`?(PASS|FAIL)', 'IgnoreCase')
        if ($v.Success) { $cur.verify = $v.Groups[1].Value.ToUpperInvariant(); continue }
        $s = [regex]::Match($line, '^\s*-\s*Stats\s*:\s*(.*)$')
        if ($s.Success) {
            foreach ($pair in [regex]::Matches($s.Groups[1].Value, '([A-Za-z_]+)=([^\s,;]+)')) {
                $cur.stats[$pair.Groups[1].Value.ToLowerInvariant()] = $pair.Groups[2].Value.Trim('`')
            }
        }
    }
    return , @($list)
}

function Get-IntStat {
    param($Entry, [string]$Key)
    if (-not $Entry.stats.ContainsKey($Key)) { return $null }
    $n = 0
    if ([int]::TryParse($Entry.stats[$Key], [ref]$n)) { return $n }
    return $null
}

function Get-FirstDate {
    param($Entries, [string]$Command)
    foreach ($e in $Entries) { if ($e.command -eq $Command -and $e.date) { return $e.date } }
    return $null
}

function Get-DayDiff {
    param($From, $To)
    if (-not $From -or -not $To) { return $null }
    return [int](($To - $From).TotalDays)
}

# ------------------------------------------------------------------- read items

if (-not (Test-Path -LiteralPath $WorkRoot -PathType Container)) {
    Write-Error "No .work folder at $WorkRoot"
    exit 1
}
$sinceDate = $null
if ($Since) {
    $sinceDate = ConvertTo-Date $Since
    if (-not $sinceDate) { Write-Error "-Since must be yyyy-MM-dd"; exit 1 }
}

$gateFiles = @("spec", "plan", "bug", "stories", "milestones", "refine", "quick")
$items = New-Object System.Collections.ArrayList

foreach ($dir in (Get-ChildItem -LiteralPath $WorkRoot -Directory | Sort-Object Name)) {
    $nm = [regex]::Match($dir.Name, '^(\d+|L\d+)-(.+)$')
    if (-not $nm.Success) { continue }

    $entries = Get-Entries (Read-Text (Join-Path $dir.FullName "progress.md"))
    $repos = Read-Text (Join-Path $dir.FullName "repos.md")
    $lane = $null; $repoCount = $null
    if ($repos) {
        $lm = [regex]::Match($repos, '(?mi)^\s*Lane\s*:\s*([a-z]+)')
        if ($lm.Success) { $lane = $lm.Groups[1].Value.ToLowerInvariant() }
        $repoCount = @([regex]::Matches($repos, '(?m)^\|\s*\d+\s*\|')).Count
    }

    $started = Get-FirstDate $entries "start"
    if (-not $started -and $entries.Count -gt 0) { $started = $entries[0].date }
    if ($sinceDate -and (-not $started -or $started -lt $sinceDate)) { continue }

    # Phases: day each command first ran.
    $phase = [ordered]@{}
    foreach ($c in @("start", "spec", "bug", "quick", "plan", "tasks", "do-task", "review", "pr")) {
        $d = Get-FirstDate $entries $c
        $phase[$c] = if ($d) { $d.ToString("yyyy-MM-dd") } else { $null }
    }
    $prDate = Get-FirstDate $entries "pr"

    # Rounds: how many times a drafting command or review ran.
    $rounds = [ordered]@{}
    foreach ($c in @("spec", "plan", "bug", "quick", "review")) {
        $rounds[$c] = @($entries | Where-Object { $_.command -eq $c }).Count
    }

    # Gates: /approve entries with Stats gate= and file=.
    $gates = New-Object System.Collections.ArrayList
    foreach ($e in ($entries | Where-Object { $_.command -eq "approve" })) {
        $g = if ($e.stats.ContainsKey("gate")) { $e.stats["gate"].ToLowerInvariant() } else { "unknown" }
        $f = if ($e.stats.ContainsKey("file")) { $e.stats["file"].ToLowerInvariant() -replace '\.md$', '' } else { "unknown" }
        [void]$gates.Add([ordered]@{ file = $f; result = $g })
    }

    # Questions and assumptions, summed over entries that report them.
    $q = $null; $a = $null
    foreach ($e in $entries) {
        $qi = Get-IntStat $e "questions"; if ($null -ne $qi) { $q = [int]$q + $qi }
        $ai = Get-IntStat $e "assumptions"; if ($null -ne $ai) { $a = [int]$a + $ai }
    }

    # Build: /do-task runs, failed verifies, failed full-suite checks.
    $doTasks = @($entries | Where-Object { $_.command -eq "do-task" })
    $verifyFails = @($doTasks | Where-Object { $_.verify -eq "FAIL" -or ($_.stats.ContainsKey("verify") -and $_.stats["verify"] -eq "FAIL") }).Count
    $fullFails = @($doTasks | Where-Object { $_.stats.ContainsKey("full") -and $_.stats["full"] -eq "FAIL" }).Count

    # Tasks.
    $tasksText = Read-Text (Join-Path $dir.FullName "tasks.md")
    $tasksTotal = $null; $tasksDone = $null; $tasksAdded = $null
    if ($tasksText) {
        $tasksTotal = @([regex]::Matches($tasksText, '(?m)^##\s*\[[ xX]\]\s*Task\s+\d+')).Count
        $tasksDone = @([regex]::Matches($tasksText, '(?m)^##\s*\[[xX]\]\s*Task\s+\d+')).Count
        $planned = $null
        foreach ($e in ($entries | Where-Object { $_.command -in @("tasks", "bug", "quick") })) {
            $t = Get-IntStat $e "tasks"; if ($null -ne $t) { $planned = $t }
        }
        if ($null -ne $planned) { $tasksAdded = [math]::Max(0, $tasksTotal - $planned) }
    }

    # Review.
    $reviewText = Read-Text (Join-Path $dir.FullName "review.md")
    $verdict = $null
    $findings = [ordered]@{ blocker = $null; shouldFix = $null; nit = $null }
    $categories = [ordered]@{}
    if ($reviewText) {
        $vm = [regex]::Match($reviewText, '(?mi)^\s*Verdict\s*:\s*(READY|CHANGES NEEDED)')
        if ($vm.Success) { $verdict = $vm.Groups[1].Value.ToUpperInvariant() }
        $findings.blocker = 0; $findings.shouldFix = 0; $findings.nit = 0
        foreach ($row in [regex]::Matches($reviewText, '(?m)^\|\s*\d+\s*\|\s*(Blocker|Should fix|Nit)\s*\|(?:\s*([a-z-]+)\s*\|)?')) {
            switch ($row.Groups[1].Value) {
                "Blocker" { $findings.blocker++ }
                "Should fix" { $findings.shouldFix++ }
                "Nit" { $findings.nit++ }
            }
            $cat = $row.Groups[2].Value
            if ($cat) { if ($categories.Contains($cat)) { $categories[$cat]++ } else { $categories[$cat] = 1 } }
        }
    }

    [void]$items.Add([ordered]@{
        id              = $nm.Groups[1].Value
        name            = $nm.Groups[2].Value
        lane            = $lane
        repos           = $repoCount
        started         = if ($started) { $started.ToString("yyyy-MM-dd") } else { $null }
        prDrafted       = if ($prDate) { $prDate.ToString("yyyy-MM-dd") } else { $null }
        daysToPr        = Get-DayDiff $started $prDate
        phases          = $phase
        rounds          = $rounds
        gates           = @($gates)
        questions       = $q
        assumptions     = $a
        doTaskRuns      = $doTasks.Count
        verifyFails     = $verifyFails
        fullSuiteFails  = $fullFails
        tasksTotal      = $tasksTotal
        tasksDone       = $tasksDone
        tasksAdded      = $tasksAdded
        retro           = (Test-Path -LiteralPath (Join-Path $dir.FullName "retro.md"))
        verdict         = $verdict
        findings        = $findings
        categories      = $categories
    })
}

# ------------------------------------------------------------------- rollups

$all = @($items)
$withPr = @($all | Where-Object { $null -ne $_.daysToPr })
$reviewed = @($all | Where-Object { $_.rounds.review -gt 0 })

$gateSummary = [ordered]@{}
foreach ($f in $gateFiles + @("unknown")) {
    $rows = @($all | ForEach-Object { $_.gates } | Where-Object { $_.file -eq $f })
    if ($rows.Count -eq 0) { continue }
    $unchanged = @($rows | Where-Object { $_.result -eq "unchanged" }).Count
    $edited = @($rows | Where-Object { $_.result -eq "edited" }).Count
    $gateSummary[$f] = [ordered]@{
        approvals     = $rows.Count
        unchanged     = $unchanged
        edited        = $edited
        noHash        = @($rows | Where-Object { $_.result -eq "no-hash" -or $_.result -eq "unknown" }).Count
        unchangedRate = Get-Rate $unchanged ($unchanged + $edited)
    }
}

$lanes = [ordered]@{}
foreach ($i in $all) {
    $l = if ($i.lane) { $i.lane } else { "unknown" }
    if ($lanes.Contains($l)) { $lanes[$l]++ } else { $lanes[$l] = 1 }
}

$catTotals = [ordered]@{}
foreach ($i in $all) { foreach ($k in $i.categories.Keys) { if ($catTotals.Contains($k)) { $catTotals[$k] += $i.categories[$k] } else { $catTotals[$k] = $i.categories[$k] } } }

$qItems = @($all | Where-Object { $null -ne $_.questions })
$doTaskRuns = ($all | ForEach-Object { [int]$_.doTaskRuns } | Measure-Object -Sum).Sum
$verifyFails = ($all | ForEach-Object { [int]$_.verifyFails } | Measure-Object -Sum).Sum

$summary = [ordered]@{
    items                 = $all.Count
    lanes                 = $lanes
    reachedPr             = $withPr.Count
    medianDaysToPr        = Get-Median @($withPr | ForEach-Object { [double]$_.daysToPr })
    medianReviewRounds    = Get-Median @($reviewed | ForEach-Object { [double]$_.rounds.review })
    multiReviewRate       = Get-Rate @($reviewed | Where-Object { $_.rounds.review -gt 1 }).Count $reviewed.Count
    questions             = if ($qItems.Count) { ($qItems | ForEach-Object { [int]$_.questions } | Measure-Object -Sum).Sum } else { $null }
    assumptions           = if ($qItems.Count) { ($qItems | ForEach-Object { [int]$_.assumptions } | Measure-Object -Sum).Sum } else { $null }
    doTaskRuns            = [int]$doTaskRuns
    verifyFailRate        = Get-Rate ([int]$verifyFails) ([int]$doTaskRuns)
    fullSuiteFails        = [int](($all | ForEach-Object { [int]$_.fullSuiteFails } | Measure-Object -Sum).Sum)
    tasksAddedByReview    = [int](($all | Where-Object { $null -ne $_.tasksAdded } | ForEach-Object { [int]$_.tasksAdded } | Measure-Object -Sum).Sum)
    blockers              = [int](($all | Where-Object { $null -ne $_.findings.blocker } | ForEach-Object { $_.findings.blocker } | Measure-Object -Sum).Sum)
    findingCategories     = $catTotals
    retros                = @($all | Where-Object { $_.retro }).Count
}

$result = [ordered]@{
    version   = $SchemaVersion
    generated = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    since     = if ($sinceDate) { $sinceDate.ToString("yyyy-MM-dd") } else { $null }
    summary   = $summary
    gates     = $gateSummary
    items     = $all
}

if ($AsJson) {
    $json = $result | ConvertTo-Json -Depth 8 -Compress
    # ASCII only, like New-Dashboard.ps1 -AsJson.
    $json = [regex]::Replace($json, '[^\x00-\x7F]', { param($m) '\u{0:x4}' -f [int][char]$m.Value })
    Write-Output $json
    exit 0
}

# ------------------------------------------------------------------- markdown

function Show {
    param($Value, [string]$Suffix = "")
    if ($null -eq $Value) { return "n/a" }
    return "$Value$Suffix"
}

$out = New-Object System.Collections.Generic.List[string]
$out.Add("# Pipeline stats")
$out.Add("")
$range = if ($sinceDate) { "since $($sinceDate.ToString('yyyy-MM-dd'))" } else { "all time" }
$laneText = (@($lanes.Keys | ForEach-Object { "$_ $($lanes[$_])" }) -join ", ")
$out.Add("$($summary.items) work items ($range): $laneText")
$out.Add("")
$out.Add("| Measure | Value |")
$out.Add("|---|---|")
$out.Add("| Reached /pr | $($summary.reachedPr) |")
$out.Add("| Median days, /start to /pr | $(Show $summary.medianDaysToPr) |")
$out.Add("| Median review rounds | $(Show $summary.medianReviewRounds) |")
$out.Add("| Items needing 2+ reviews | $(Show $summary.multiReviewRate '%') |")
$out.Add("| Questions asked / assumptions written | $(Show $summary.questions) / $(Show $summary.assumptions) |")
$out.Add("| /do-task runs, verify failure rate | $($summary.doTaskRuns), $(Show $summary.verifyFailRate '%') |")
$out.Add("| Full-suite failures caught in /do-task | $($summary.fullSuiteFails) |")
$out.Add("| Tasks added after /tasks (mostly review fixes) | $($summary.tasksAddedByReview) |")
$out.Add("| Review Blockers (current review.md files) | $($summary.blockers) |")
$out.Add("| Items with a /retro | $($summary.retros) of $($summary.reachedPr) that reached /pr |")
$out.Add("")
$out.Add("## Gates")
$out.Add("")
if ($gateSummary.Count -eq 0) {
    $out.Add("No /approve entries with gate stats yet (Core 2.22.0+).")
}
else {
    $out.Add("| Gate | Approvals | Approved as written | Edited first | No hash | As-written rate |")
    $out.Add("|---|---|---|---|---|---|")
    foreach ($k in $gateSummary.Keys) {
        $g = $gateSummary[$k]
        $out.Add("| $k | $($g.approvals) | $($g.unchanged) | $($g.edited) | $($g.noHash) | $(Show $g.unchangedRate '%') |")
    }
    $out.Add("")
    $out.Add("A high as-written rate on a gate with few later problems means the gate may be a rubber stamp.")
}
if ($catTotals.Count -gt 0) {
    $out.Add("")
    $out.Add("## Review findings by category")
    $out.Add("")
    $out.Add("| Category | Findings |")
    $out.Add("|---|---|")
    foreach ($k in ($catTotals.Keys | Sort-Object { -$catTotals[$_] })) { $out.Add("| $k | $($catTotals[$k]) |") }
}
$out.Add("")
$out.Add("## Items")
$out.Add("")
$out.Add("| Item | Lane | Days to /pr | Spec/plan/bug rounds | Reviews | Blockers | Tasks (added) | Verify fails |")
$out.Add("|---|---|---|---|---|---|---|---|")
foreach ($i in $all) {
    $r = $i.rounds
    $tasks = if ($null -eq $i.tasksTotal) { "n/a" } else { "$($i.tasksTotal) ($(Show $i.tasksAdded))" }
    $out.Add("| $($i.id)-$($i.name) | $(Show $i.lane) | $(Show $i.daysToPr) | $($r.spec)/$($r.plan)/$($r.bug) | $($r.review) | $(Show $i.findings.blocker) | $tasks | $($i.verifyFails) |")
}
$out | ForEach-Object { Write-Output $_ }
