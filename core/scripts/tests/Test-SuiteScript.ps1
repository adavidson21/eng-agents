<#
.SYNOPSIS
    Self-test for Test-Suite.ps1, with no Playwright: a fake runner (node) writes a Playwright-shaped JSON report
    from a fixture, so reading the table, before and after, flaky, new tests and [AC-n] coverage are all checked.
#>
$ErrorActionPreference = "Stop"
$script = Join-Path $PSScriptRoot "Test-Suite.ps1"
$fails = 0
function Check([string]$Name, [bool]$Ok, [string]$Got) {
    if ($Ok) { Write-Output "ok   $Name" } else { Write-Output "FAIL $Name (got: $Got)"; $script:fails++ }
}
function Last($Lines) { return "$(@($Lines)[-1])" }
function Commit([string]$Repo, [string]$Msg) {
    & git -C $Repo add -A
    & git -C $Repo -c user.email=t@t -c user.name=t commit -qm $Msg
}
function Spec([string]$Title, [string]$Status, [string]$Err) {
    $r = @{ status = 'passed' }
    if ($Err) { $r = @{ status = 'failed'; error = @{ message = $Err } } }
    return @{ title = $Title; tests = @(@{ status = $Status; results = @($r) }) }
}
function Report($Specs) {
    # Two files: e2e/orders.spec.ts (old) and e2e/refund.spec.ts (the item's new file), one describe block each.
    $old = @($Specs | Where-Object { $_.f -eq 'old' } | ForEach-Object { $_.s })
    $new = @($Specs | Where-Object { $_.f -eq 'new' } | ForEach-Object { $_.s })
    $suites = @(@{ title = 'orders.spec.ts'; file = 'orders.spec.ts'; specs = @(); suites = @(@{ title = 'Orders'; file = 'orders.spec.ts'; specs = $old }) })
    if ($new.Count) { $suites += @{ title = 'refund.spec.ts'; file = 'refund.spec.ts'; specs = @(); suites = @(@{ title = 'Refund'; file = 'refund.spec.ts'; specs = $new }) } }
    return (@{ suites = $suites; stats = @{} } | ConvertTo-Json -Depth 12)
}

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { Write-Output "Node is not installed: skipped."; exit 0 }

$root = Join-Path ([IO.Path]::GetTempPath()) ("suite-test-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Path $root | Out-Null
try {
    $repo = Join-Path $root "repo"
    New-Item -ItemType Directory -Path (Join-Path $repo "e2e") -Force | Out-Null
    & git -C $repo init -q 2>$null
    # The fake runner copies report.json to Playwright's JSON output and exits with the code in exit.txt.
    Set-Content -LiteralPath (Join-Path $repo "fake.mjs") -Value @'
import fs from "node:fs";
fs.copyFileSync("report.json", process.env.PLAYWRIGHT_JSON_OUTPUT_NAME);
console.log("args: " + process.argv.slice(2).join(" "));
process.exit(Number(fs.readFileSync("exit.txt", "utf8").trim()) || 0);
'@
    Set-Content -LiteralPath (Join-Path $repo "e2e/orders.spec.ts") -Value "// old"
    Set-Content -LiteralPath (Join-Path $repo "exit.txt") -Value "1"
    Set-Content -LiteralPath (Join-Path $repo "report.json") -Value (Report @(
        @{ f = 'old'; s = (Spec 'lists orders' 'expected') },
        @{ f = 'old'; s = (Spec 'exports csv' 'unexpected' 'Expected 3 rows') }))
    Commit $repo init
    & git -C $repo branch base

    $wf = Join-Path $root "work"
    New-Item -ItemType Directory -Path $wf | Out-Null
    $guide = Join-Path $repo "AGENTS.md"

    Set-Content -LiteralPath $guide -Value "# Guide`n`n## Commands`n"
    $r = & $script -WorkFolder $wf -Repo $repo -Guide $guide -Name before
    Check "no table: skipped" ((Last $r) -match '^Tests: SKIPPED the repo guide has no Regression tests table') (Last $r)

    Set-Content -LiteralPath $guide -Value "# Guide`n`n## Regression tests`n`n| Field | Value |`n|---|---|`n| Command | <command> |`n"
    $r = & $script -WorkFolder $wf -Repo $repo -Guide $guide -Name before
    Check "template placeholder is not a command" ((Last $r) -match 'has no Regression tests table') (Last $r)

    Set-Content -LiteralPath $guide -Value "# Guide`n`n## Regression tests`n`n| Field | Value |`n|---|---|`n| Command | ``node fake.mjs`` |`n| Runner | playwright |`n| Folder | ``e2e/`` |`n`n## Other`n"
    $r = & $script -WorkFolder $wf -Repo $repo -Guide $guide -Name before
    Check "before: an old failure fails the before run" ((Last $r) -match '^Tests: FAIL 1 failed, 1 passed') (Last $r)
    $b = Get-Content -LiteralPath (Join-Path $wf "tests/results-before.json") -Raw | ConvertFrom-Json
    Check "before: the failure is recorded with its describe block and error" ($b.failures[0].title -eq 'Orders > exports csv' -and $b.failures[0].error -eq 'Expected 3 rows') ($b.failures | ConvertTo-Json -Compress)
    Check "the JSON reporter and one retry are added" ((Get-Content -LiteralPath (Join-Path $wf "tests/log-before.txt") -Raw) -match '--reporter=line,json --retries=1') (Get-Content -LiteralPath (Join-Path $wf "tests/log-before.txt") -Raw)

    # The item adds refund.spec.ts with two acceptance tests; one old test turned flaky; the old failure stays.
    Set-Content -LiteralPath (Join-Path $repo "e2e/refund.spec.ts") -Value "// new"
    Set-Content -LiteralPath (Join-Path $repo "report.json") -Value (Report @(
        @{ f = 'old'; s = (Spec 'lists orders' 'flaky') },
        @{ f = 'old'; s = (Spec 'exports csv' 'unexpected' 'Expected 3 rows') },
        @{ f = 'new'; s = (Spec 'shows the reason field [AC-2]' 'expected') },
        @{ f = 'new'; s = (Spec 'saves a reason [AC-1]' 'expected') }))
    Commit $repo item
    $r = & $script -WorkFolder $wf -Repo $repo -Guide $guide -Name after -Base base
    Check "after: old failure and flaky do not fail it" ((Last $r) -eq 'Tests: PASS 2 passed, 2 new (AC-1, AC-2), 1 flaky, 1 failing before this change') (Last $r)
    $a = Get-Content -LiteralPath (Join-Path $wf "tests/results-after.json") -Raw | ConvertFrom-Json
    Check "after: results file" ($a.verdict -eq 'pass' -and $a.flaky -eq 1 -and @($a.newTests).Count -eq 2 -and @($a.preExisting).Count -eq 1 -and (@($a.acceptance) -join ',') -eq 'AC-1,AC-2') ($a | ConvertTo-Json -Compress -Depth 4)

    # A test that passed before now fails: a regression.
    Set-Content -LiteralPath (Join-Path $repo "report.json") -Value (Report @(
        @{ f = 'old'; s = (Spec 'lists orders' 'unexpected' 'Timed out') },
        @{ f = 'old'; s = (Spec 'exports csv' 'unexpected' 'Expected 3 rows') },
        @{ f = 'new'; s = (Spec 'saves a reason [AC-1]' 'expected') }))
    $r = & $script -WorkFolder $wf -Repo $repo -Guide $guide -Name after -Base base
    Check "after: a newly failing old test fails the run" ((Last $r) -match '^Tests: FAIL 1 failed, 1 passed, 1 new \(AC-1\), 1 failing before this change\. First: Orders > lists orders \(orders.spec.ts\)$') (Last $r)

    # No report: skipped, never failed.
    Remove-Item -LiteralPath (Join-Path $repo "report.json")
    $r = & $script -WorkFolder $wf -Repo $repo -Guide $guide -Name after
    Check "no report: skipped" ((Last $r) -match '^Tests: SKIPPED the suite wrote no Playwright report') (Last $r)

    # Another runner: exit code only.
    Set-Content -LiteralPath $guide -Value "# Guide`n`n## Regression tests`n`n| Field | Value |`n|---|---|`n| Command | ``node fake.mjs`` |`n| Runner | other |`n"
    $r = & $script -WorkFolder $wf -Repo $repo -Guide $guide -Name after
    Check "other runner, exit 1: fail" ((Last $r) -match '^Tests: FAIL the suite failed \(other, exit code 1\)') (Last $r)
    Set-Content -LiteralPath (Join-Path $repo "exit.txt") -Value "0"
    Set-Content -LiteralPath (Join-Path $repo "report.json") -Value "{}"
    $r = & $script -WorkFolder $wf -Repo $repo -Guide $guide -Name after
    Check "other runner, exit 0: pass" ((Last $r) -match '^Tests: PASS the suite passed \(other') (Last $r)

    $r = & $script -WorkFolder $wf -Repo (Join-Path $root "missing") -Guide $guide -Name after
    Check "missing repo folder: skipped" ((Last $r) -match '^Tests: SKIPPED no repo folder') (Last $r)
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
if ($fails) { Write-Output "$fails test suite script check(s) failed."; exit 1 }
Write-Output "All test suite script checks passed."
