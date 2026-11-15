<#
.SYNOPSIS
  Self-test for Get-PipelineStats.ps1, Set-DraftHash.ps1 and Test-DraftHash.ps1. Writes only to a temp folder.
  Run: pwsh -NoProfile -File core/scripts/stats/Test-PipelineStats.ps1   (also works in Windows PowerShell 5.1)
#>
$ErrorActionPreference = "Stop"

$failed = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = "") {
    if ($Ok) { Write-Output "ok   $Name" } else { Write-Output "FAIL $Name $Detail"; $script:failed++ }
}

$ps = (Get-Process -Id $PID).Path
$stats = Join-Path $PSScriptRoot "Get-PipelineStats.ps1"
$work = Join-Path (Split-Path $PSScriptRoot -Parent) "work"
function Run([string]$Script, [string[]]$Arguments) {
    $ErrorActionPreference = "Continue"
    $out = & $ps -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments 2>&1 | Out-String
    return @{ Out = $out.Trim(); Code = $LASTEXITCODE }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ("stats-" + [guid]::NewGuid().ToString("N"))
$wr = Join-Path $root ".work"
$enc = New-Object System.Text.UTF8Encoding($false)
function Put([string]$Rel, [string]$Text) {
    $p = Join-Path $wr $Rel
    New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force | Out-Null
    [IO.File]::WriteAllText($p, $Text, $enc)
}

try {
    # ---------------------------------------------------------------- draft hash
    $spec = "# Spec: 1 Thing`r`n`r`nStatus: DRAFT`r`n`r`n## Goal`r`n`r`nDo the thing.`r`n"
    Put "draft/spec.md" $spec
    $specPath = Join-Path $wr "draft/spec.md"

    $r = Run (Join-Path $work "Test-DraftHash.ps1") @("-Path", $specPath)
    Check "draft hash: no line yet -> no-hash" ($r.Out -eq "no-hash") $r.Out

    $r = Run (Join-Path $work "Set-DraftHash.ps1") @("-Path", $specPath)
    $after = [IO.File]::ReadAllText($specPath)
    Check "draft hash: stamp prints the line" ($r.Out -match '^Draft-hash: [0-9a-f]{12}$') $r.Out
    Check "draft hash: line goes right after Status, CRLF kept" ($after -match "Status: DRAFT`r`nDraft-hash: [0-9a-f]{12}`r`n`r`n## Goal") $after

    $r = Run (Join-Path $work "Test-DraftHash.ps1") @("-Path", $specPath)
    Check "draft hash: untouched -> unchanged" ($r.Out -eq "unchanged") $r.Out

    [IO.File]::WriteAllText($specPath, $after.Replace("Status: DRAFT", "Status: APPROVED").Replace("`r`n", "`n"), $enc)
    $r = Run (Join-Path $work "Test-DraftHash.ps1") @("-Path", $specPath)
    Check "draft hash: Status flip and line endings -> still unchanged" ($r.Out -eq "unchanged") $r.Out

    [IO.File]::WriteAllText($specPath, $after.Replace("Do the thing.", "Do the other thing."), $enc)
    $r = Run (Join-Path $work "Test-DraftHash.ps1") @("-Path", $specPath)
    Check "draft hash: body edit -> edited" ($r.Out -eq "edited") $r.Out

    $r = Run (Join-Path $work "Set-DraftHash.ps1") @("-Path", $specPath)
    $again = [IO.File]::ReadAllText($specPath)
    Check "draft hash: re-stamp replaces, never duplicates" (@([regex]::Matches($again, 'Draft-hash:')).Count -eq 1) $again
    $r = Run (Join-Path $work "Test-DraftHash.ps1") @("-Path", $specPath)
    Check "draft hash: after re-stamp -> unchanged" ($r.Out -eq "unchanged") $r.Out

    Put "draft/notes.md" "# No status here`n"
    $r = Run (Join-Path $work "Set-DraftHash.ps1") @("-Path", (Join-Path $wr "draft/notes.md"))
    Check "draft hash: file without Status -> exit 1" ($r.Code -eq 1) $r.Out
    $r = Run (Join-Path $work "Test-DraftHash.ps1") @("-Path", (Join-Path $wr "draft/missing.md"))
    Check "draft hash: missing file -> exit 1" ($r.Code -eq 1) $r.Out

    # ---------------------------------------------------------------- stats fixture
    Put "101-export-retry/repos.md" @'
# Repos for 101

Lane: feature

| Order | Repo folder | Branch | Shared? | Why it is involved | Base |
|---|---|---|---|---|---|
| 1 | api | dev/feature/101-export-retry | no | API | origin/main |
| 2 | ui | dev/feature/101-export-retry | no | UI | origin/main |
'@
    Put "101-export-retry/progress.md" @'
# Progress: 101 Export retry

---

## 2026-11-01 | /start | planner

- Did: started
- Stats: questions=0

## 2026-11-01 | /spec | planner

- Did: wrote spec
- Stats: questions=2 assumptions=3

## 2026-11-02 | /approve | planner

- Did: approved spec.md
- Stats: gate=edited file=spec

## 2026-11-02 | /plan | planner

- Did: wrote plan
- Stats: questions=0 assumptions=1

## 2026-11-02 | /approve | planner

- Did: approved plan.md
- Stats: gate=unchanged file=plan

## 2026-11-02 | /tasks | planner

- Did: 2 tasks
- Stats: tasks=2

## 2026-11-03 | /do-task | implementer

- Did: task 1
- Verify: `dotnet test` -> FAIL
- Stats: verify=FAIL attempts=3

## 2026-11-03 | /do-task | implementer

- Did: task 1
- Verify: `dotnet test` -> PASS
- Stats: verify=PASS full=FAIL

## 2026-11-04 | /review | reviewer

- Did: review, 1 Blocker

## 2026-11-04 | /do-task | implementer

- Did: task 3 (review fix)
- Verify: `dotnet test` -> PASS
- Stats: verify=PASS full=PASS

## 2026-11-05 | /review | reviewer

- Did: READY

## 2026-11-05 | /pr | writer

- Did: pr text
'@
    Put "101-export-retry/tasks.md" @'
# Tasks: 101

## [x] Task 1: Add retry

## [x] Task 2: Show retry

## [x] Task 3: Fix null check
'@
    Put "101-export-retry/review.md" @'
# Review: 101

Verdict: READY

| # | Severity | Category | Location | Problem | Suggested fix |
|---|---|---|---|---|---|
| 1 | Should fix | correctness | `api/A.cs:1` | x | y |
| 2 | Nit | leftovers | `api/B.cs:2` | x | y |
'@
    Put "102-null-crash/repos.md" "Lane: bug`n`n| Order | Repo folder |`n|---|---|`n| 1 | api |`n"
    Put "102-null-crash/progress.md" @'
## 2026-11-10 | /start | planner

- Did: started

## 2026-11-10 | /bug | investigator

- Did: bug.md
- Stats: tasks=2

## 2026-11-10 | /approve | planner

- Did: approved bug.md
- Stats: gate=no-hash file=bug.md
'@
    Put "L3-old-item/progress.md" @'
## 2026-10-01 | /start | planner

- Did: started (written before Stats lines)

## 2026-10-03 | /pr | writer

- Did: pr text
'@
    Put "spike-cache/findings.md" "# not a work item`n"
    Put "scope-v2/stories.md" "Status: DRAFT`n"

    $r = Run $stats @("-WorkRoot", $wr, "-AsJson")
    Check "stats: -AsJson exits 0" ($r.Code -eq 0) $r.Out
    $j = $r.Out | ConvertFrom-Json
    $byId = @{}; foreach ($i in $j.items) { $byId[$i.id] = $i }
    $a = $byId["101"]; $b = $byId["102"]; $c = $byId["L3"]

    Check "stats: schema version 1" ($j.version -eq 1)
    Check "stats: only work item folders (3)" (@($j.items).Count -eq 3) "got $(@($j.items).Count)"
    Check "stats: lane and repo count" ($a.lane -eq "feature" -and $a.repos -eq 2 -and $b.lane -eq "bug")
    Check "stats: days to /pr" ($a.daysToPr -eq 4 -and $c.daysToPr -eq 2 -and $null -eq $b.daysToPr)
    Check "stats: rounds" ($a.rounds.spec -eq 1 -and $a.rounds.plan -eq 1 -and $a.rounds.review -eq 2 -and $b.rounds.bug -eq 1)
    Check "stats: questions and assumptions summed" ($a.questions -eq 2 -and $a.assumptions -eq 4)
    Check "stats: older item has no question data" ($null -eq $c.questions)
    Check "stats: verify and full-suite failures" ($a.doTaskRuns -eq 3 -and $a.verifyFails -eq 1 -and $a.fullSuiteFails -eq 1)
    Check "stats: tasks added after /tasks" ($a.tasksTotal -eq 3 -and $a.tasksDone -eq 3 -and $a.tasksAdded -eq 1)
    Check "stats: bug lane planned tasks without tasks.md -> null" ($null -eq $b.tasksAdded)
    Check "stats: review verdict, severities, categories" ($a.verdict -eq "READY" -and $a.findings.shouldFix -eq 1 -and $a.findings.nit -eq 1 -and $a.findings.blocker -eq 0 -and $a.categories.correctness -eq 1)
    Check "stats: gates per file" ($j.gates.spec.edited -eq 1 -and $j.gates.plan.unchanged -eq 1 -and $j.gates.plan.unchangedRate -eq 100 -and $j.gates.bug.noHash -eq 1)
    Check "stats: summary medians and rates" ($j.summary.items -eq 3 -and $j.summary.reachedPr -eq 2 -and $j.summary.medianDaysToPr -eq 3 -and $j.summary.multiReviewRate -eq 100)
    Check "stats: summary verify fail rate" ($j.summary.verifyFailRate -eq 33) "got $($j.summary.verifyFailRate)"
    Check "stats: summary sums" ($j.summary.questions -eq 2 -and $j.summary.assumptions -eq 4 -and $j.summary.fullSuiteFails -eq 1 -and $j.summary.tasksAddedByReview -eq 1 -and $j.summary.doTaskRuns -eq 3) ($j.summary | ConvertTo-Json -Compress)
    Check "stats: summary finding categories" ($j.summary.findingCategories.correctness -eq 1 -and $j.summary.findingCategories.leftovers -eq 1)

    $r = Run $stats @("-WorkRoot", $wr, "-AsJson", "-Since", "2026-11-05")
    $j2 = $r.Out | ConvertFrom-Json
    Check "stats: -Since keeps items started on or after it" (@($j2.items).Count -eq 1 -and $j2.items[0].id -eq "102")

    $r = Run $stats @("-WorkRoot", $wr)
    Check "stats: markdown exits 0" ($r.Code -eq 0) $r.Out
    Check "stats: markdown has gate and item tables" ($r.Out -match '\| plan \| 1 \| 1 \| 0 \| 0 \| 100% \|' -and $r.Out -match '\| 101-export-retry \| feature \| 4 \|') $r.Out
    Check "stats: missing values show n/a" ($r.Out -match '\| L3-old-item \| n/a \| 2 \|') $r.Out

    $r = Run $stats @("-WorkRoot", (Join-Path $root "nope"))
    Check "stats: missing .work -> exit 1" ($r.Code -eq 1)

    Check "stats: retro flag and count" ($a.retro -eq $false -and $j.summary.retros -eq 0)

    # ---------------------------------------------------------------- review findings
    $find = Join-Path $PSScriptRoot "Get-ReviewFindings.ps1"
    Put "101-export-retry/history/review-2026-11-04-1.md" @'
Verdict: CHANGES NEEDED

| # | Severity | Category | Location | Problem | Suggested fix |
|---|---|---|---|---|---|
| 1 | Blocker | correctness | `api/src/Export.cs:12` | null order not handled | guard it |
'@
    Put "102-null-crash/review.md" @'
Verdict: CHANGES NEEDED

| # | Severity | Category | Location | Problem | Suggested fix |
|---|---|---|---|---|---|
| 1 | Should fix | correctness | `api\src\Orders.cs:40` | null customer | guard it |
| 2 | Nit | <category> | `ui/app/x.ts:1` | placeholder category | x |
'@
    Put "L3-old-item/review.md" @'
Verdict: READY

| # | Severity | Location | Problem | Suggested fix |
|---|---|---|---|---|
| 1 | Nit | `ui/app/list.component.ts:9` | unused import | remove it |
'@
    $r = Run $find @("-WorkRoot", $wr, "-AsJson")
    Check "findings: -AsJson exits 0" ($r.Code -eq 0) $r.Out
    $f = $r.Out | ConvertFrom-Json
    Check "findings: all rounds and items read" (@($f.findings).Count -eq 6 -and $f.itemsReviewed -eq 3) "got $(@($f.findings).Count) findings, $($f.itemsReviewed) items"
    $old = @($f.findings | Where-Object { $_.id -eq "L3" })[0]
    Check "findings: older table without category" ($old.category -eq "uncategorized" -and $old.repo -eq "ui" -and $old.problem -eq "unused import")
    $ph = @($f.findings | Where-Object { $_.problem -eq "placeholder category" })[0]
    Check "findings: placeholder category -> uncategorized" ($ph.category -eq "uncategorized")
    $top = @($f.patterns)[0]
    Check "findings: api correctness repeats across 2 items (rounds count once)" ($top.repo -eq "api" -and $top.category -eq "correctness" -and $top.itemCount -eq 2 -and $top.findings -eq 3 -and $top.blockers -eq 1 -and $top.repeats) ($top | ConvertTo-Json -Compress)
    $rep = @($f.patterns | Where-Object { $_.repeats })
    Check "findings: only patterns in 2+ items repeat (api correctness, ui uncategorized)" ($rep.Count -eq 2 -and @($rep | Where-Object { $_.repo -eq "ui" -and $_.category -eq "uncategorized" }).Count -eq 1 -and @($f.patterns | Where-Object { $_.category -eq "leftovers" -and -not $_.repeats }).Count -eq 1)
    $r = Run $find @("-WorkRoot", $wr, "-Id", "101", "-AsJson")
    $f1 = $r.Out | ConvertFrom-Json
    Check "findings: -Id keeps one item" (@($f1.findings).Count -eq 3 -and $f1.itemsReviewed -eq 1)
    $r = Run $find @("-WorkRoot", $wr)
    Check "findings: markdown lists the repeating pattern" ($r.Code -eq 0 -and $r.Out -match '\| api \| correctness \| 2 \| 3 \| 1 \|') $r.Out

    $empty = Join-Path $root "empty"
    New-Item -ItemType Directory -Path $empty -Force | Out-Null
    $r = Run $stats @("-WorkRoot", $empty, "-AsJson")
    $je = $r.Out | ConvertFrom-Json
    Check "stats: empty .work -> zero items, exit 0" ($r.Code -eq 0 -and $je.summary.items -eq 0 -and $null -eq $je.summary.medianDaysToPr) $r.Out
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failed) { Write-Output "$failed check(s) failed."; exit 1 }
Write-Output "Pipeline stats: all checks passed."
