<#
.SYNOPSIS
    Regression tests for one repo of a work item: run the repo's whole end-to-end suite and record what passed,
    what failed, what is flaky and which acceptance criteria the item's own tests cover.

.DESCRIPTION
    Reads the "## Regression tests" table in the repo guide (Command, Runner, Folder) and runs Command in the
    repo folder or its worktree. With Runner playwright (the default) it adds Playwright's JSON reporter and one
    retry, so a test that passes on its retry is reported as flaky, not failed. Results go to
    <WorkFolder>\tests\results-<Name>.json.

    - With -Name after (or pr) and a "before" run from /start, a test that already failed before the change is
      listed under preExisting and never fails the run.
    - With -Base, tests in files the branch added or changed (git diff --name-only <Base>...HEAD under Folder, or
      any *.spec.* / *.test.* / *.e2e.* file) are the item's new tests; "[AC-<n>]" in their titles says which
      acceptance criteria they cover.

    It never fails the calling command: a failing suite is "Tests: FAIL", anything that keeps the suite from
    running (no table, no result file, timeout) is "Tests: SKIPPED <why>".
    The LAST line printed is always "Tests: PASS ...", "Tests: FAIL ..." or "Tests: SKIPPED ...".

.EXAMPLE
    .\Test-Suite.ps1 -WorkFolder .work\L12-refund-reason -Repo .worktrees\L12-refund-reason\portal-ui -Guide portal-ui\AGENTS.local.md -Name after -Base origin/main
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$WorkFolder,
    [Parameter(Mandatory = $true)][string]$Repo,
    [Parameter(Mandatory = $true)][string]$Guide,
    [ValidatePattern('^[a-z0-9-]{1,30}$')][string]$Name = "after",
    [string]$Base,
    [ValidateRange(0, 3)][int]$Retries = 1,
    [int]$TimeoutSeconds = 1200
)

$ErrorActionPreference = "Stop"
function Done([string]$Line) { Write-Output $Line; exit 0 }

function Get-Table([string]$Text, [string]$Heading) {
    $rows = @{}
    if (-not $Text) { return $rows }
    $in = $false
    foreach ($line in ($Text -split "\r?\n")) {
        if ($line -match ('^\s*##\s+' + [regex]::Escape($Heading) + '\s*$')) { $in = $true; continue }
        if ($in -and $line -match '^\s*##\s') { break }
        if (-not $in) { continue }
        if ($line -match '^\s*\|\s*([^|]+?)\s*\|\s*(.*?)\s*\|\s*$') {
            $k = $Matches[1].Trim().ToLowerInvariant()
            $v = ($Matches[2] -replace '`', '').Trim()
            if ($k -eq 'field' -or $k -match '^:?-+:?$') { continue }
            if ($v -match '^<.*>$' -or $v -match '^TODO') { $v = '' }
            $rows[$k] = $v
        }
    }
    return $rows
}

function Test-IsTestFile([string]$File, [string]$Folder) {
    $f = $File -replace '\\', '/'
    if ($Folder) {
        $d = ($Folder -replace '\\', '/').Trim('/')
        if ($d -and $f.StartsWith($d + '/')) { return $true }
    }
    return ($f -match '\.(spec|test|e2e)\.[cm]?[jt]sx?$')
}

# Every test in a Playwright JSON report: file, title (describe blocks and test, joined by " > "), outcome and first error.
function Get-PlaywrightTests($Report) {
    $out = New-Object System.Collections.ArrayList
    $walk = $null
    $walk = {
        param($Suite, [string[]]$Path, [string]$File)
        $f = $File
        if ($Suite.file) { $f = [string]$Suite.file }
        $here = $Path
        if ($Suite.title -and $Suite.title -ne $Suite.file -and $Suite.title -ne $f) { $here = @($Path) + @([string]$Suite.title) }
        foreach ($spec in @($Suite.specs)) {
            if (-not $spec) { continue }
            $sf = $f
            if ($spec.file) { $sf = [string]$spec.file }
            foreach ($t in @($spec.tests)) {
                if (-not $t) { continue }
                $err = $null
                foreach ($r in @($t.results)) {
                    if ($r -and $r.error -and $r.error.message) { $err = [string]$r.error.message; break }
                }
                if ($err) { $err = (($err -replace '\x1b\[[0-9;]*m', '') -split "\r?\n")[0]; if ($err.Length -gt 300) { $err = $err.Substring(0, 300) } }
                $title = ((@($here) + @([string]$spec.title)) | Where-Object { $_ }) -join ' > '
                [void]$out.Add([pscustomobject]@{ file = ($sf -replace '\\', '/'); title = $title; status = [string]$t.status; error = $err })
            }
        }
        foreach ($s in @($Suite.suites)) { if ($s) { & $walk $s $here $f } }
    }
    foreach ($s in @($Report.suites)) { if ($s) { & $walk $s @() '' } }
    return $out
}

function Join-Key($T) { return "$($T.file)|$($T.title)" }

# ------------------------------------------------------------------ read the table

if (-not (Test-Path -LiteralPath $Guide)) { Done "Tests: SKIPPED no repo guide at $Guide" }
$table = Get-Table (Get-Content -LiteralPath $Guide -Raw) 'Regression tests'
if (-not $table['command']) { Done "Tests: SKIPPED the repo guide has no Regression tests table (add one with /onboard-repo)" }
if (-not (Test-Path -LiteralPath $Repo)) { Done "Tests: SKIPPED no repo folder at $Repo" }
$runner = 'playwright'
if ($table['runner']) { $runner = $table['runner'].ToLowerInvariant() }
$folder = $table['folder']

$out = Join-Path $WorkFolder "tests"
New-Item -ItemType Directory -Path $out -Force | Out-Null
$repoFull = (Resolve-Path -LiteralPath $Repo).Path
$json = Join-Path $out "playwright-$Name.json"
$log = Join-Path $out "log-$Name.txt"
Remove-Item -LiteralPath $json, $log -ErrorAction SilentlyContinue

# ------------------------------------------------------------------ run it

$cmd = $table['command']
if ($runner -eq 'playwright') {
    $extra = "--reporter=line,json --retries=$Retries"
    if ($cmd -match '^\s*(npm|pnpm|yarn)\s+(run\s+)?\S+' -and $cmd -notmatch '\s--(\s|$)') { $cmd = "$cmd -- $extra" } else { $cmd = "$cmd $extra" }
}

$isWin = ($env:OS -eq 'Windows_NT')
$psi = New-Object System.Diagnostics.ProcessStartInfo
if ($isWin) { $psi.FileName = 'cmd.exe'; $psi.Arguments = '/d /s /c "' + $cmd + ' > "' + $log + '" 2>&1"' }
else { $psi.FileName = '/bin/sh'; $psi.Arguments = '-c "' + ($cmd -replace '"', '\"') + ' > \"' + $log + '\" 2>&1"' }
$psi.WorkingDirectory = $repoFull
$psi.UseShellExecute = $false
$psi.EnvironmentVariables['PLAYWRIGHT_JSON_OUTPUT_NAME'] = $json
$psi.EnvironmentVariables['CI'] = '1'
$proc = [System.Diagnostics.Process]::Start($psi)
if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
    try { $proc.Kill() } catch {}
    Done "Tests: SKIPPED the suite ran longer than $TimeoutSeconds seconds"
}
$code = $proc.ExitCode

$result = [ordered]@{
    version = 1; name = $Name; verdict = 'skipped'; reason = $null; runner = $runner; command = $table['command']
    passed = 0; failed = 0; flaky = 0; skipped = 0
    failures = @(); preExisting = @(); flakyTests = @(); newTests = @(); acceptance = @()
    at = (Get-Date).ToUniversalTime().ToString('o')
}
function Save-Result {
    $file = Join-Path $out "results-$Name.json"
    ($result | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $file -Encoding UTF8
}

# ------------------------------------------------------------------ other runners: pass or fail only

if ($runner -ne 'playwright') {
    if ($code -eq 0) { $result.verdict = 'pass'; Save-Result; Done "Tests: PASS the suite passed ($runner, no per-test details)" }
    $last = @(Get-Content -LiteralPath $log -ErrorAction SilentlyContinue | Where-Object { $_.Trim() } | Select-Object -Last 1)
    $result.verdict = 'fail'; $result.reason = "exit code $code"; Save-Result
    Done "Tests: FAIL the suite failed ($runner, exit code $code): $($last -join '')"
}

if (-not (Test-Path -LiteralPath $json)) {
    $last = @(Get-Content -LiteralPath $log -ErrorAction SilentlyContinue | Where-Object { $_.Trim() } | Select-Object -Last 1)
    $result.reason = "no Playwright report (exit code $code)"; Save-Result
    Done "Tests: SKIPPED the suite wrote no Playwright report (exit code $code): $($last -join '')"
}
try { $report = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json } catch { Done "Tests: SKIPPED the Playwright report could not be read" }

$tests = Get-PlaywrightTests $report

# Tests that already failed before the change are not this item's.
$before = @{}
$beforeFile = Join-Path $out "results-before.json"
if ($Name -ne 'before' -and (Test-Path -LiteralPath $beforeFile)) {
    try {
        $b = Get-Content -LiteralPath $beforeFile -Raw | ConvertFrom-Json
        foreach ($x in (@($b.failures) + @($b.preExisting))) { if ($x) { $before[(Join-Key $x)] = $true } }
    } catch {}
}

# The item's own tests: in test files the branch added or changed.
$changed = @{}
if ($Base) {
    $names = & git -C $repoFull diff --name-only "$Base...HEAD" 2>$null
    if ($LASTEXITCODE -eq 0) { foreach ($n in @($names)) { if ($n -and (Test-IsTestFile $n $folder)) { $changed[($n -replace '\\', '/')] = $true } } }
}
function Test-Changed([string]$File) {
    foreach ($k in $changed.Keys) { if ($File -eq $k -or $k.EndsWith('/' + $File) -or $File.EndsWith('/' + $k)) { return $true } }
    return $false
}

$fail = New-Object System.Collections.ArrayList
$pre = New-Object System.Collections.ArrayList
$flaky = New-Object System.Collections.ArrayList
$new = New-Object System.Collections.ArrayList
$acs = New-Object System.Collections.ArrayList
foreach ($t in $tests) {
    $row = [pscustomobject]@{ file = $t.file; title = $t.title }
    switch ($t.status) {
        'expected' { $result.passed++ }
        'flaky' { $result.flaky++; [void]$flaky.Add($row) }
        'skipped' { $result.skipped++ }
        default {
            $row = [pscustomobject]@{ file = $t.file; title = $t.title; error = $t.error }
            if ($before.ContainsKey((Join-Key $t))) { [void]$pre.Add($row) } else { $result.failed++; [void]$fail.Add($row) }
        }
    }
    if ($changed.Count -and (Test-Changed $t.file)) {
        [void]$new.Add([pscustomobject]@{ file = $t.file; title = $t.title; status = $t.status })
        foreach ($m in [regex]::Matches($t.title, '\[(AC-\d+)\]')) { if (-not $acs.Contains($m.Groups[1].Value)) { [void]$acs.Add($m.Groups[1].Value) } }
    }
}
$result.failures = @($fail | Select-Object -First 30)
$result.preExisting = @($pre | Select-Object -First 30)
$result.flakyTests = @($flaky | Select-Object -First 30)
$result.newTests = @($new | Select-Object -First 50)
$result.acceptance = @($acs | Sort-Object { [int]($_ -replace '\D', '') })

if (-not $tests.Count) { $result.reason = 'no tests found'; Save-Result; Done "Tests: SKIPPED the suite found no tests" }

$parts = @("$($result.passed) passed")
if ($new.Count) {
    $p = "$($new.Count) new"
    if ($acs.Count) { $p += " (" + ($result.acceptance -join ', ') + ")" }
    $parts += $p
}
if ($result.flaky) { $parts += "$($result.flaky) flaky" }
if ($pre.Count) { $parts += "$($pre.Count) failing before this change" }
if ($result.skipped) { $parts += "$($result.skipped) skipped" }

if ($result.failed) {
    $result.verdict = 'fail'; Save-Result
    $first = $fail[0]
    Done ("Tests: FAIL $($result.failed) failed, " + ($parts -join ', ') + ". First: $($first.title) ($($first.file))")
}
$result.verdict = 'pass'; Save-Result
Done ("Tests: PASS " + ($parts -join ', '))
