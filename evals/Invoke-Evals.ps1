<#
.SYNOPSIS
    Runs Tandem's commands against the eval fixtures with a real model and scores each run.

.DESCRIPTION
    For each case in evals/cases/*.json and each run:
      1. builds a fresh workspace in a temp folder (the repo map, sample-api as its own git repo,
         and the case's .work files),
      2. runs `opencode run --command <command> "<arguments>"` from the workspace root,
      3. grades what the agent left behind with the case's grader (evals/lib/Graders.ps1).
    A run passes when every check passes. Each case runs -Runs times (default 3), because one run of a
    model says little. Results go to evals/results/<core version>-<time>.json, and the summary compares
    each case with the previous results file.

    Before running: install this checkout (`./install.ps1`), so opencode uses the commands you are testing.
    The script warns when the installed version is not this checkout's core/VERSION.

    Nothing here touches your real workspace or ADO. The fixtures are made up, so the results hold no
    company data and can be committed (commit the baseline you compare against).

    Permissions: opencode asks before some commands (git push, deletes, web requests). With nobody to
    answer, a run that needs one stalls until -TimeoutMinutes. -AutoApprove passes `--auto`, which approves
    anything not denied. The workspace is a throwaway temp folder with no remote, but read the guards first.

.EXAMPLE
    ./evals/Invoke-Evals.ps1

.EXAMPLE
    ./evals/Invoke-Evals.ps1 -Case spec-basic, review-planted -Runs 5 -Model anthropic/claude-sonnet-5-5

.EXAMPLE
    ./evals/Invoke-Evals.ps1 -Case do-task -SetupOnly     # build the workspace and print its path
#>
[CmdletBinding()]
param(
    [string[]]$Case,
    [int]$Runs = 3,
    # provider/model, passed to opencode as --model. Default: your opencode default model.
    [string]$Model,
    [string]$Opencode = "opencode",
    [switch]$AutoApprove,
    [int]$TimeoutMinutes = 20,
    [switch]$KeepWorkspaces,
    [switch]$SetupOnly,
    [string]$OutDir = (Join-Path $PSScriptRoot "results")
)

$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSVersion.Major -lt 6) { Remove-TypeData System.Array -ErrorAction SilentlyContinue }
. (Join-Path $PSScriptRoot "lib/EvalLib.ps1")
. (Join-Path $PSScriptRoot "lib/Graders.ps1")

$version = ([IO.File]::ReadAllText((Join-Path $script:RepoRoot "core/VERSION"))).Trim()
$caseFiles = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot "cases") -Filter *.json | Sort-Object Name)
if ($Case) {
    $Case = @($Case | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $unknown = @($Case | Where-Object { -not (Test-Path (Join-Path $PSScriptRoot "cases/$_.json")) })
    if ($unknown) { throw "Unknown case(s): $($unknown -join ', '). Known: $(@($caseFiles | ForEach-Object { $_.BaseName }) -join ', ')" }
    $caseFiles = @($caseFiles | Where-Object { $Case -contains $_.BaseName })
}

if ($SetupOnly) {
    foreach ($cf in $caseFiles) {
        $c = Read-Case $cf.FullName
        $ws = New-EvalWorkspace $c (New-TempDir "eval-$($cf.BaseName)")
        Write-Output "$($cf.BaseName): $($ws.Root)"
        Write-Output "  then, from that folder: $Opencode run --command $($c.command) `"$($c.arguments)`""
    }
    exit 0
}

# ------------------------------------------------------------------ preflight

$oc = Get-Command $Opencode -ErrorAction SilentlyContinue
if (-not $oc) { throw "opencode not found ('$Opencode'). Install it, or pass -Opencode <path>." }
$hasDotnet = [bool](Get-Command dotnet -ErrorAction SilentlyContinue)

$home2 = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$manifest = Join-Path $home2 ".config/opencode/eng-agents/manifest.json"
$installed = $null
if (Test-Path -LiteralPath $manifest) {
    try { $m = Get-Content -Raw $manifest | ConvertFrom-Json; if ($m.components -and $m.components.core) { $installed = "$($m.components.core.version)" } } catch { }
}
if ($installed -ne $version) {
    Write-Warning "Installed Tandem is '$installed', this checkout is $version. Run ./install.ps1 first, or these results test the installed commands, not this checkout."
}

# opencode may be a .cmd shim on Windows; Process.Start needs cmd.exe for those.
function Start-Opencode([string]$WorkDir, [string[]]$OcArgs, [string]$Log) {
    $quoted = @($OcArgs | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    if ($oc.Source -match '\.(cmd|bat)$') { $psi.FileName = $env:ComSpec; $psi.Arguments = "/c `"`"$($oc.Source)`" $quoted`"" }
    else { $psi.FileName = $oc.Source; $psi.Arguments = $quoted }
    $psi.WorkingDirectory = $WorkDir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    $done = $p.WaitForExit($TimeoutMinutes * 60 * 1000)
    if (-not $done) { try { $p.Kill() } catch { } ; $p.WaitForExit(10000) | Out-Null }
    [IO.File]::WriteAllText($Log, "exit: $(if ($done) { $p.ExitCode } else { 'timeout' })`n--- stdout`n$($outTask.Result)`n--- stderr`n$($errTask.Result)", $script:Utf8)
    return [pscustomobject]@{ TimedOut = (-not $done); ExitCode = $(if ($done) { $p.ExitCode } else { $null }) }
}

# ------------------------------------------------------------------ run

$logs = New-TempDir "eval-logs"
$results = New-Object System.Collections.ArrayList
foreach ($cf in $caseFiles) {
    $c = Read-Case $cf.FullName
    $name = $cf.BaseName
    $needs = @(Get-CaseList $c.needs)
    if (($needs -contains "dotnet") -and -not $hasDotnet) {
        Write-Output "skip $name (needs dotnet)"
        [void]$results.Add([ordered]@{ case = $name; skipped = "needs dotnet"; runs = @() })
        continue
    }
    $runList = New-Object System.Collections.ArrayList
    for ($i = 1; $i -le $Runs; $i++) {
        $root = New-TempDir "eval-$name"
        $started = Get-Date
        $ws = New-EvalWorkspace $c $root
        $ocArgs = @("run", "--command", $c.command)
        if ($Model) { $ocArgs += @("--model", $Model) }
        if ($AutoApprove) { $ocArgs += "--auto" }
        $ocArgs += $c.arguments
        $log = Join-Path $logs "$name-$i.log"
        $proc = Start-Opencode $root $ocArgs $log
        $checks = @()
        try { $checks = @(& $c.grader $ws) }
        catch { $checks = @([pscustomobject]@{ Check = "grader ran"; Pass = $false; Detail = $_.Exception.Message }) }
        $failedChecks = @($checks | Where-Object { -not $_.Pass })
        $pass = ($checks.Count -gt 0 -and $failedChecks.Count -eq 0 -and -not $proc.TimedOut)
        $secs = [int]((Get-Date) - $started).TotalSeconds
        Write-Output ("{0,-16} run {1}: {2} ({3}s){4}" -f $name, $i, $(if ($pass) { "PASS" } else { "FAIL" }), $secs, $(if ($proc.TimedOut) { " timed out" } else { "" }))
        foreach ($f in $failedChecks) { Write-Output "    - $($f.Check)$(if ($f.Detail) { ": $($f.Detail)" })" }
        [void]$runList.Add([ordered]@{
            run = $i; pass = $pass; seconds = $secs; timedOut = $proc.TimedOut; exitCode = $proc.ExitCode
            failed = @($failedChecks | ForEach-Object { [ordered]@{ check = $_.Check; detail = $_.Detail } }); checks = $checks.Count
            log = $log; workspace = $(if ($KeepWorkspaces) { $root } else { $null })
        })
        if (-not $KeepWorkspaces) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }
    $passes = @($runList | Where-Object { $_.pass }).Count
    [void]$results.Add([ordered]@{ case = $name; passes = $passes; total = $runList.Count; rate = [math]::Round(100.0 * $passes / [math]::Max(1, $runList.Count)); runs = @($runList) })
}

# ------------------------------------------------------------------ save and compare

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$previousFile = @(Get-ChildItem -LiteralPath $OutDir -Filter *.json -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1)
$previous = @{}
if ($previousFile.Count -eq 1) {
    $pj = Get-Content -Raw $previousFile[0].FullName | ConvertFrom-Json
    foreach ($r in $pj.cases) { if ($null -ne $r.rate) { $previous[$r.case] = [int]$r.rate } }
}
$doc = [ordered]@{
    version = 1; tandem = $version; installed = $installed; model = $(if ($Model) { $Model } else { "opencode default" })
    runsPerCase = $Runs; autoApprove = [bool]$AutoApprove; date = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    cases = @($results)
}
$outFile = Join-Path $OutDir "$version-$stamp.json"
[IO.File]::WriteAllText($outFile, ($doc | ConvertTo-Json -Depth 8), $script:Utf8)

Write-Output ""
Write-Output "| Case | Passed | Rate | Previous | Change |"
Write-Output "|---|---|---|---|---|"
$drops = 0
foreach ($r in $results) {
    if ($r.skipped) { Write-Output "| $($r.case) | skipped ($($r.skipped)) | | | |"; continue }
    $prev = if ($previous.ContainsKey($r.case)) { "$($previous[$r.case])%" } else { "n/a" }
    $chg = ""
    if ($previous.ContainsKey($r.case)) {
        $d = $r.rate - $previous[$r.case]
        $chg = if ($d -lt 0) { "**$d**"; $drops++ } elseif ($d -gt 0) { "+$d" } else { "same" }
    }
    Write-Output "| $($r.case) | $($r.passes)/$($r.total) | $($r.rate)% | $prev | $chg |"
}
Write-Output ""
if ($previousFile.Count -eq 1) { Write-Output "Compared with $($previousFile[0].Name)." }
if ($drops) { Write-Output "$drops case(s) dropped. Read their failed checks and logs before releasing." }
Write-Output "Logs: $logs"
Write-Output "Results: $outFile"
