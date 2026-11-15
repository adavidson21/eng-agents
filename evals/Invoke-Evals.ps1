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
    model says little.

    Arms (-Arm): `tandem` (default) runs the case's Tandem command, or its `steps` (several commands in one
    workspace, with gates approved by this script, as autopilot would). `baseline` runs the case's plain
    `baseline.prompt` with Tandem left out: opencode starts with a config folder that has none of Tandem's
    agents, commands, rules or memory, only your own settings (model, providers, permissions). `both` runs
    each arm on the same cases, so the summary can show the lift: Tandem's pass rate minus the baseline's.
    Only cases with a `baseline` take part in the baseline arm. Both arms get the same workspace, repo map
    and repo guide, so the lift measures Tandem's phases, not its knowledge files. Results go to evals/results/<core version>-<time>.json, and the summary compares
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
    ./evals/Invoke-Evals.ps1 -Case feature-outcome -Arm both -Runs 3 -AutoApprove   # Tandem against a plain prompt

.EXAMPLE
    ./evals/Invoke-Evals.ps1 -Case do-task -SetupOnly     # build the workspace and print its path
#>
[CmdletBinding()]
param(
    [string[]]$Case,
    [int]$Runs = 3,
    # provider/model, passed to opencode as --model. Default: your opencode default model.
    [string]$Model,
    # Several models in one run (the model matrix): every case and arm runs on each. Overrides -Model.
    [string[]]$Models,
    [string]$Opencode = "opencode",
    [ValidateSet("tandem", "baseline", "both")]
    [string]$Arm = "tandem",
    [switch]$AutoApprove,
    [int]$TimeoutMinutes = 20,
    [switch]$KeepWorkspaces,
    [switch]$SetupOnly,
    # Self-test only (evals/Test-Harness.ps1): graders skip their dotnet checks, and cases that need dotnet run anyway.
    [switch]$NoExec,
    # Only the cases whose prompts changed since the newest results file that ran them (or never ran).
    [switch]$Affected,
    # Every case, tandem arm, compared with the newest results file; exits 1 when a case dropped.
    [switch]$Release,
    # Exit 1 when a tandem case dropped against the newest results file (on by default with -Release).
    [switch]$Gate,
    # Refuse to start more than this many model runs (cases x arms x runs x models). Raise it on purpose.
    [int]$MaxRuns = 30,
    # An experiment: a folder that mirrors core/ (for example <folder>/commands/plan.md). The tandem arm runs a
    # scratch install with these files laid over core/; your real Tandem is not touched.
    [string]$Overlay,
    # A short name for this run, kept in the results file (an experiment's id, for example).
    [string]$Label,
    # The writing judge's model (provider/model, free or paid). Without it, writing cases skip their rubric.
    [string]$Judge,
    [string]$OutDir = (Join-Path $PSScriptRoot "results")
)

$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSVersion.Major -lt 6) { Remove-TypeData System.Array -ErrorAction SilentlyContinue }
. (Join-Path $PSScriptRoot "lib/EvalLib.ps1")
. (Join-Path $PSScriptRoot "lib/Graders.ps1")
. (Join-Path $PSScriptRoot "lib/Experiments.ps1")

$version = ([IO.File]::ReadAllText((Join-Path $script:RepoRoot "core/VERSION"))).Trim()
$caseFiles = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot "cases") -Filter *.json | Sort-Object Name)
if ($Case) {
    $Case = @($Case | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $unknown = @($Case | Where-Object { -not (Test-Path (Join-Path $PSScriptRoot "cases/$_.json")) })
    if ($unknown) { throw "Unknown case(s): $($unknown -join ', '). Known: $(@($caseFiles | ForEach-Object { $_.BaseName }) -join ', ')" }
    $caseFiles = @($caseFiles | Where-Object { $Case -contains $_.BaseName })
}
if ($Release -and $Case) { throw "-Release runs every case; leave out -Case." }
if ($Release -and $Arm -ne "tandem") { throw "-Release runs the tandem arm; use -Arm both separately for the lift." }
if ($Release) { $Gate = $true }
if ($Affected) {
    $aff = Get-AffectedCases -CaseFiles $caseFiles -ResultsDir $OutDir
    if (-not $aff.Run.Count) { Write-Output "Nothing changed since the last results: every selected case is up to date."; exit 0 }
    foreach ($n in $aff.Run) { Write-Output "affected: $n ($($aff.Why[$n]))" }
    $caseFiles = @($caseFiles | Where-Object { $aff.Run -contains $_.BaseName })
}
$modelList = if ($Models) { @($Models | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) } else { @($Model) }

# The arms a case runs in: tandem always; baseline only when the case has a baseline prompt.
function Get-CaseArms($c) {
    $list = @()
    if ($Arm -ne "baseline") { $list += "tandem" }
    if ($Arm -ne "tandem" -and $c.baseline -and $c.baseline.prompt) { $list += "baseline" }
    return $list
}

# The Tandem arm's steps: the case's `steps`, or its one command.
function Get-TandemSteps($c) {
    if ($c.steps) { return @($c.steps) }
    return @([pscustomobject]@{ command = $c.command; arguments = $c.arguments })
}

function Get-StepLabel($step) {
    if ($step.approve) { return "approve $($step.approve)" }
    $label = "/$($step.command) $($step.arguments)"
    if ($step.eachTask) { $label += " (each task)" }
    return $label
}

# The baseline arm's workspace: the same repo and repo map, but no .work files (those are Tandem's).
function New-BaselineWorkspace($c, [string]$Root) {
    $plain = $c | Select-Object * -ExcludeProperty work
    return New-EvalWorkspace $plain $Root
}

$planned = 0
foreach ($cf in $caseFiles) { $planned += @(Get-CaseArms (Read-Case $cf.FullName)).Count * $Runs * $modelList.Count }
if (-not $SetupOnly -and $planned -gt $MaxRuns) { throw "This would start $planned model runs, more than -MaxRuns $MaxRuns. Pick fewer cases, runs or models, or raise -MaxRuns." }

if ($SetupOnly) {
    foreach ($cf in $caseFiles) {
        $c = Read-Case $cf.FullName
        foreach ($a in (Get-CaseArms $c)) {
            if ($a -eq "baseline") {
                $ws = New-BaselineWorkspace $c (New-TempDir "eval-$($cf.BaseName)-baseline")
                Write-Output "$($cf.BaseName) (baseline): $($ws.Root)"
                Write-Output "  then, from that folder, with Tandem left out: $Opencode run `"$($c.baseline.prompt)`""
                continue
            }
            $ws = New-EvalWorkspace $c (New-TempDir "eval-$($cf.BaseName)")
            Write-Output "$($cf.BaseName): $($ws.Root)"
            foreach ($st in (Get-TandemSteps $c)) {
                if ($st.approve) { Write-Output "  then: set Status: APPROVED in .work/$($c.workItem)/$($st.approve)" }
                else { Write-Output "  then, from that folder: $Opencode run --command $($st.command) `"$($st.arguments)`"$(if ($st.eachTask) { '  (once per task, {n} = task number)' })" }
            }
        }
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
if ($installed -ne $version -and $Arm -ne "baseline") {
    Write-Warning "Installed Tandem is '$installed', this checkout is $version. Run ./install.ps1 first, or these results test the installed commands, not this checkout."
}

# The baseline arm's config folder, made once per run: your opencode settings without Tandem.
$baselineConfig = $null
if ($Arm -ne "tandem") {
    $xdg = New-TempDir "eval-plain-config"
    $baselineConfig = $xdg
    $plainDir = Join-Path $xdg "opencode"
    New-Item -ItemType Directory -Path $plainDir -Force | Out-Null
    $userDir = if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME "opencode" } else { Join-Path $home2 ".config/opencode" }
    $plainConfig = New-PlainOpencodeConfig -UserDir $userDir
    [IO.File]::WriteAllText((Join-Path $plainDir $plainConfig.Name), $plainConfig.Text, $script:Utf8)
    Write-Output "Baseline arm: opencode config without Tandem in $plainDir ($($plainConfig.Note))"
}

# The writing judge runs with Tandem left out, like the baseline.
if ($Judge) {
    $env:EVAL_JUDGE_MODEL = $Judge
    $env:EVAL_OPENCODE = $oc.Source
    if (-not $baselineConfig) {
        $judgeXdg = New-TempDir "eval-judge-config"
        $jd = Join-Path $judgeXdg "opencode"; New-Item -ItemType Directory -Path $jd -Force | Out-Null
        $userDirJ = if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME "opencode" } else { Join-Path $home2 ".config/opencode" }
        $pcJ = New-PlainOpencodeConfig -UserDir $userDirJ
        [IO.File]::WriteAllText((Join-Path $jd $pcJ.Name), $pcJ.Text, $script:Utf8)
        $env:EVAL_PLAIN_CONFIG = $judgeXdg
    }
    else { $env:EVAL_PLAIN_CONFIG = $baselineConfig }
}

# An experiment's Tandem: a scratch install with the overlay laid over core/.
$experiment = $null
if ($Overlay -and $Arm -ne "baseline") {
    $userDir2 = if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME "opencode" } else { Join-Path $home2 ".config/opencode" }
    $experiment = New-ExperimentConfig -Overlay $Overlay -UserDir $userDir2
    $script:CommandInfos = @(Get-CommandInfos -Core (Join-Path $experiment.Repo "core"))
    Write-Output "Experiment: Tandem with $Overlay laid over core/, installed in $($experiment.XdgConfigHome)"
}
$tandemEnv = if ($experiment) { @{ XDG_CONFIG_HOME = $experiment.XdgConfigHome } } else { @{} }

# opencode may be a .cmd shim on Windows; Process.Start needs cmd.exe for those.
function Start-Opencode([string]$WorkDir, [string[]]$OcArgs, [string]$Log, [hashtable]$Env = @{}) {
    # Raw JSON events, so tokens, cost, tool calls and questions can be counted (Get-RunUsage).
    $OcArgs = @($OcArgs[0], "--format", "json") + @($OcArgs | Select-Object -Skip 1)
    $quoted = @($OcArgs | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    if ($oc.Source -match '\.(cmd|bat)$') { $psi.FileName = $env:ComSpec; $psi.Arguments = "/c `"`"$($oc.Source)`" $quoted`"" }
    else { $psi.FileName = $oc.Source; $psi.Arguments = $quoted }
    $psi.WorkingDirectory = $WorkDir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    foreach ($k in $Env.Keys) { $psi.EnvironmentVariables[$k] = $Env[$k] }
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    $done = $p.WaitForExit($TimeoutMinutes * 60 * 1000)
    if (-not $done) { try { $p.Kill() } catch { } ; $p.WaitForExit(10000) | Out-Null }
    $prior = if (Test-Path -LiteralPath $Log) { [IO.File]::ReadAllText($Log) + "`n" } else { "" }
    [IO.File]::WriteAllText($Log, $prior + "=== opencode $quoted`nexit: $(if ($done) { $p.ExitCode } else { 'timeout' })`n--- stdout`n$($outTask.Result)`n--- stderr`n$($errTask.Result)", $script:Utf8)
    return [pscustomobject]@{ TimedOut = (-not $done); ExitCode = $(if ($done) { $p.ExitCode } else { $null }); Usage = (Get-RunUsage $outTask.Result) }
}

function Invoke-Step($step, $c, $ws, [string]$Log) {
    $t0 = Get-Date
    $label = Get-StepLabel $step
    if ($step.approve) {
        $ok = Approve-GateFile -Work $ws.Work -Name $step.approve
        return [ordered]@{ step = $label; ok = $ok; seconds = [int]((Get-Date) - $t0).TotalSeconds; timedOut = $false; usage = (New-Usage) }
    }
    $argsList = @("$($step.arguments)")
    if ($step.eachTask) {
        $open = @((Get-Tasks (Read-WorkFile $ws "tasks.md")) | Where-Object { -not $_.Done } | Select-Object -First $script:MaxTasks)
        if (-not $open.Count) { return [ordered]@{ step = $label; ok = $false; seconds = 0; timedOut = $false; detail = "no open tasks in tasks.md"; usage = (New-Usage) } }
        $argsList = @($open | ForEach-Object { "$($step.arguments)" -replace '\{n\}', "$($_.N)" })
    }
    $timedOut = $false
    $exit = 0
    $usage = New-Usage
    foreach ($a in $argsList) {
        $ocArgs = @("run", "--command", $step.command)
        if ($Model) { $ocArgs += @("--model", $Model) }
        if ($AutoApprove) { $ocArgs += "--auto" }
        $ocArgs += $a
        $proc = Start-Opencode $ws.Root $ocArgs $Log $tandemEnv
        $usage = Add-Usage $usage $proc.Usage
        if ($proc.TimedOut) { $timedOut = $true; break }
        if ($proc.ExitCode) { $exit = $proc.ExitCode }
    }
    return [ordered]@{ step = $label; ok = (-not $timedOut -and $exit -eq 0); seconds = [int]((Get-Date) - $t0).TotalSeconds; timedOut = $timedOut; runs = $argsList.Count; usage = $usage }
}

# ------------------------------------------------------------------ run

$script:MaxTasks = 8
$logs = New-TempDir "eval-logs"
$results = New-Object System.Collections.ArrayList
foreach ($Model in $modelList) {
$modelName = if ($Model) { $Model } else { "opencode default" }
if ($modelList.Count -gt 1) { Write-Output ""; Write-Output "== model $modelName" }
foreach ($cf in $caseFiles) {
    $c = Read-Case $cf.FullName
    $name = $cf.BaseName
    $arms = @(Get-CaseArms $c)
    if (-not $arms.Count) {
        Write-Output "skip $name (no baseline prompt)"
        continue
    }
    $needs = @(Get-CaseList $c.needs)
    if (($needs -contains "dotnet") -and -not $hasDotnet -and -not $NoExec) {
        Write-Output "skip $name (needs dotnet)"
        foreach ($a in $arms) { [void]$results.Add([ordered]@{ case = $name; arm = $a; model = $modelName; skipped = "needs dotnet"; runs = @() }) }
        continue
    }
    foreach ($a in $arms) {
        $tag = if ($a -eq "baseline") { "$name (baseline)" } else { $name }
        $runList = New-Object System.Collections.ArrayList
        for ($i = 1; $i -le $Runs; $i++) {
            $root = New-TempDir "eval-$name-$a"
            $started = Get-Date
            $log = Join-Path $logs "$name-$a-$(($modelName -replace '[^\w.-]', '_'))-$i.log"
            $steps = @()
            if ($a -eq "baseline") {
                $ws = New-BaselineWorkspace $c $root
                $ocArgs = @("run")
                if ($Model) { $ocArgs += @("--model", $Model) }
                if ($AutoApprove) { $ocArgs += "--auto" }
                $ocArgs += "$($c.baseline.prompt)"
                $t0 = Get-Date
                $proc = Start-Opencode $root $ocArgs $log @{ XDG_CONFIG_HOME = $baselineConfig }
                $steps = @([ordered]@{ step = "plain prompt"; ok = (-not $proc.TimedOut -and -not $proc.ExitCode); seconds = [int]((Get-Date) - $t0).TotalSeconds; timedOut = $proc.TimedOut; usage = $proc.Usage })
            }
            else {
                $ws = New-EvalWorkspace $c $root
                foreach ($st in (Get-TandemSteps $c)) {
                    $r = Invoke-Step $st $c $ws $log
                    $steps += $r
                    if ($r.timedOut) { break }
                }
            }
            $timedOut = [bool](@($steps | Where-Object { $_.timedOut }).Count)
            $checks = @()
            try { $checks = @(& $c.grader $ws -NoExec:$NoExec) }
            catch { $checks = @([pscustomobject]@{ Check = "grader ran"; Pass = $false; Detail = $_.Exception.Message }) }
            $failedChecks = @($checks | Where-Object { -not $_.Pass })
            $pass = ($checks.Count -gt 0 -and $failedChecks.Count -eq 0 -and -not $timedOut)
            $secs = [int]((Get-Date) - $started).TotalSeconds
            $runUsage = New-Usage
            foreach ($st2 in $steps) { if ($st2.usage) { $runUsage = Add-Usage $runUsage $st2.usage } }
            $verifyFails = Get-VerifyFails $ws
            Write-Output ("{0,-26} run {1}: {2} ({3}s){4}" -f $tag, $i, $(if ($pass) { "PASS" } else { "FAIL" }), $secs, $(if ($timedOut) { " timed out" } else { "" }))
            foreach ($f in $failedChecks) { Write-Output "    - $($f.Check)$(if ($f.Detail) { ": $($f.Detail)" })" }
            [void]$runList.Add([ordered]@{
                run = $i; pass = $pass; seconds = $secs; timedOut = $timedOut
                tokens = (Get-UsageTokens $runUsage); cost = $runUsage.cost; toolCalls = $runUsage.toolCalls; questions = $runUsage.questions
                usageKnown = $runUsage.known; verifyFails = $verifyFails
                steps = @($steps | ForEach-Object { $u = $_.usage; $o = [ordered]@{}; foreach ($k in $_.Keys) { if ($k -ne 'usage') { $o[$k] = $_[$k] } }; if ($u) { $o.tokens = $u.input + $u.output + $u.reasoning; $o.cost = $u.cost }; $o })
                failed = @($failedChecks | ForEach-Object { [ordered]@{ check = $_.Check; detail = $_.Detail } }); checks = $checks.Count
                log = $log; workspace = $(if ($KeepWorkspaces) { $root } else { $null })
            })
            if (-not $KeepWorkspaces) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
        }
        $passes = @($runList | Where-Object { $_.pass }).Count
        $entry = [ordered]@{
            case = $name; arm = $a; model = $modelName; filesHash = $(if ($a -eq "tandem") { Get-CaseFilesHash $c } else { $null })
            passes = $passes; total = $runList.Count
            rate = [math]::Round(100.0 * $passes / [math]::Max(1, $runList.Count))
            passAll = ($runList.Count -gt 0 -and $passes -eq $runList.Count)
            meanSeconds = $(if ($runList.Count) { $t = 0; foreach ($rr in $runList) { $t += [int]$rr.seconds }; [int]($t / $runList.Count) } else { 0 })
            promptTokens = (Get-CasePromptTokens $c $a)
        }
        $sumUp = Get-CaseUsageSummary $runList $passes
        foreach ($k in $sumUp.Keys) { $entry[$k] = $sumUp[$k] }
        $entry.runs = @($runList)
        [void]$results.Add($entry)
    }
}
}
if ($Judge) { if ($judgeXdg) { Remove-Item -LiteralPath $judgeXdg -Recurse -Force -ErrorAction SilentlyContinue }; Remove-Item Env:EVAL_JUDGE_MODEL, Env:EVAL_OPENCODE, Env:EVAL_PLAIN_CONFIG -ErrorAction SilentlyContinue }
if ($experiment) { Remove-Item -LiteralPath $experiment.XdgConfigHome, $experiment.Repo -Recurse -Force -ErrorAction SilentlyContinue }
if ($baselineConfig) { Remove-Item -LiteralPath $baselineConfig -Recurse -Force -ErrorAction SilentlyContinue }

# ------------------------------------------------------------------ save and compare

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
# Compare with the newest results file that was not an experiment.
$previousFile = @(Get-ChildItem -LiteralPath $OutDir -Filter *.json -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Where-Object {
    try { -not ((Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json).overlay) } catch { $false } } | Select-Object -First 1)
$previous = @{}
if ($previousFile.Count -eq 1) {
    $pj = Get-Content -Raw $previousFile[0].FullName | ConvertFrom-Json
    foreach ($r in $pj.cases) {
        $pa = if ($r.arm) { "$($r.arm)" } else { "tandem" }
        $pm = if ($r.model) { "$($r.model)" } else { "$($pj.model)" }
        if ($null -ne $r.rate) { $previous["$($r.case)|$pa|$pm"] = [int]$r.rate }
    }
}
$armsRun = @($results | ForEach-Object { $_.arm } | Select-Object -Unique)
$modelNames = @($modelList | ForEach-Object { if ($_) { $_ } else { "opencode default" } })
$doc = [ordered]@{
    version = 4; tandem = $version; installed = $installed; model = $modelNames[0]; models = @($modelNames)
    runsPerCase = $Runs; autoApprove = [bool]$AutoApprove; arms = @($armsRun); date = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    kind = $(if ($Overlay) { "experiment" } elseif ($Release) { "release" } elseif ($Affected) { "affected" } elseif ($Arm -ne "tandem") { "lift" } else { "custom" })
    judge = $(if ($Judge) { $Judge } else { $null })
    label = $(if ($Label) { $Label } else { $null }); overlay = $(if ($Overlay) { $Overlay } else { $null })
    compareTo = $(if ($previousFile.Count -eq 1) { $previousFile[0].Name } else { $null })
    cases = @($results)
}
$outFile = Join-Path $OutDir "$version-$stamp.json"
[IO.File]::WriteAllText($outFile, ($doc | ConvertTo-Json -Depth 10), $script:Utf8)
# An experiment run is listed in its experiment.json, so Bench can show before and after.
if ($Overlay) {
    $em = [regex]::Match(([IO.Path]::GetFullPath($Overlay) -replace '\\', '/'), '/experiments/([a-z]+-[a-z0-9-]+)/overlay/?$')
    if ($em.Success) { try { Set-ExperimentStatus $em.Groups[1].Value $null (Split-Path $outFile -Leaf) } catch { } }
}

Write-Output ""
Write-Output "| Case | Arm | Model | Passed | Rate | Every run | Tokens/run | Questions | Previous | Change |"
Write-Output "|---|---|---|---|---|---|---|---|---|---|"
$drops = 0
foreach ($r in $results) {
    if ($r.skipped) { Write-Output "| $($r.case) | $($r.arm) | $($r.model) | skipped ($($r.skipped)) | | | | | | |"; continue }
    $key = "$($r.case)|$($r.arm)|$($r.model)"
    $prev = if ($previous.ContainsKey($key)) { "$($previous[$key])%" } else { "n/a" }
    $chg = ""
    if ($previous.ContainsKey($key)) {
        $d = $r.rate - $previous[$key]
        $chg = if ($d -lt 0) { "**$d**"; if ($r.arm -eq "tandem") { $drops++ } } elseif ($d -gt 0) { "+$d" } else { "same" }
    }
    $tok = if ($null -ne $r.meanTokens) { "$($r.meanTokens)" } else { "n/a" }
    Write-Output "| $($r.case) | $($r.arm) | $($r.model) | $($r.passes)/$($r.total) | $($r.rate)% | $(if ($r.passAll) { 'yes' } else { 'no' }) | $tok | $($r.meanQuestions) | $prev | $chg |"
}

$lift = @(Get-Lift $results)
if ($lift.Count) {
    Write-Output ""
    Write-Output "| Case | Model | Tandem | Baseline | Lift |"
    Write-Output "|---|---|---|---|---|"
    foreach ($l in $lift) { Write-Output "| $($l.case) | $($l.model) | $($l.tandem)% | $($l.baseline)% | $(if ($l.lift -gt 0) { '+' })$($l.lift) |" }
}
Write-Output ""
if ($previousFile.Count -eq 1) { Write-Output "Compared with $($previousFile[0].Name)." }
if ($drops) { Write-Output "$drops case(s) dropped. Read their failed checks and logs before releasing." }
Write-Output "Logs: $logs"
Write-Output "Results: $outFile"
if ($Gate -and $drops) { Write-Output "Gate: $drops case(s) dropped against $($previousFile[0].Name)."; exit 1 }
exit 0
