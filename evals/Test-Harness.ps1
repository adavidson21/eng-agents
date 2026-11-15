<#
.SYNOPSIS
  Checks Invoke-Evals.ps1 itself with a fake opencode (no model, no dotnet): the Tandem arm runs a case's steps in
  order and approves gates between them, the baseline arm runs the plain prompt with Tandem's rules out of the config
  folder, and the results file holds both arms and the lift. Run in CI on Linux; needs bash.
  Run: pwsh -NoProfile -File evals/Test-Harness.ps1
#>
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib/EvalLib.ps1")
. (Join-Path $PSScriptRoot "lib/Graders.ps1")

$failed = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = "") {
    if ($Ok) { Write-Output "ok   $Name" } else { Write-Output "FAIL $Name $Detail"; $script:failed++ }
}

# ---- helpers, no opencode

$tmp = New-TempDir "harness"
try {
    $w = Join-Path $tmp "work"; New-Item -ItemType Directory -Path $w | Out-Null
    [IO.File]::WriteAllText((Join-Path $w "spec.md"), "# Spec`nStatus: DRAFT`n", $script:Utf8)
    Check "Approve-GateFile approves a DRAFT" ((Approve-GateFile -Work $w -Name "spec.md") -and ([IO.File]::ReadAllText((Join-Path $w "spec.md")) -match '(?m)^Status: APPROVED$'))
    Check "Approve-GateFile is false for a missing file" (-not (Approve-GateFile -Work $w -Name "plan.md"))

    $u = Join-Path $tmp "user"; New-Item -ItemType Directory -Path $u | Out-Null
    [IO.File]::WriteAllText((Join-Path $u "opencode.json"), '{"model":"p/m","instructions":["x/memory.md"],"agent":{"a":{}},"permission":{"edit":"allow"}}', $script:Utf8)
    $pc = New-PlainOpencodeConfig -UserDir $u
    $o = $pc.Text | ConvertFrom-Json
    Check "plain config keeps your model and permissions" (($o.model -eq "p/m") -and $o.permission)
    Check "plain config drops Tandem's instructions and agents" (-not $o.PSObject.Properties["instructions"] -and -not $o.PSObject.Properties["agent"])
    $pc2 = New-PlainOpencodeConfig -UserDir (Join-Path $tmp "none")
    Check "plain config without an opencode.json is empty" ($pc2.Text -match 'schema' -and $pc2.Name -eq "opencode.json")

    $u = Get-RunUsage ("noise`n" + '{"type":"step_finish","part":{"tokens":{"input":5,"output":3,"reasoning":2,"cache":{"read":1,"write":0}},"cost":0.5}}' + "`n" + '{"type":"tool_use","part":{"tool":"question"}}' + "`n" + '{"type":"tool_use","part":{"tool":"bash"}}' + "`n{broken")
    Check "Get-RunUsage adds tokens, cost, tool calls and questions" ($u.known -and (Get-UsageTokens $u) -eq 10 -and $u.cacheRead -eq 1 -and $u.cost -eq 0.5 -and $u.toolCalls -eq 2 -and $u.questions -eq 1)
    Check "Get-RunUsage on plain text knows nothing" (-not (Get-RunUsage "hello").known)

    $sizes = @(Get-PromptSizes)
    $cmdCount = @(Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot "core/commands") -Filter *.md).Count
    $plan = @($sizes | Where-Object { $_.command -eq "plan" })[0]
    Check "Get-PromptSizes covers every command" ($sizes.Count -eq $cmdCount -and @($sizes | Where-Object { $_.tokens -le 0 }).Count -eq 0) "$($sizes.Count) of $cmdCount"
    Check "plan loads the planner agent and AGENTS.md" ($plan.agent -eq "planner" -and $plan.agentChars -gt 0 -and $plan.baseChars -gt 0)

    $infos = @(Get-CommandInfos)
    $spec = @($infos | Where-Object { $_.command -eq "spec" })[0]
    Check "spec reads its template and its hash is 12 hex" (($spec.files -contains "core/templates/spec.md") -and $spec.hash -match '^[0-9a-f]{12}$' -and $spec.readTokens -gt 0)
    $core2 = Join-Path $tmp "core2"
    Copy-Item -LiteralPath (Join-Path $script:RepoRoot "core") -Destination $core2 -Recurse
    Add-Content -LiteralPath (Join-Path $core2 "templates/spec.md") -Value "`nchanged"
    $spec2 = @(Get-CommandInfos -Core $core2 | Where-Object { $_.command -eq "spec" })[0]
    Check "changing a template a command reads changes its hash" ($spec2.hash -ne $spec.hash)

    $lift = @(Get-Lift @([pscustomobject]@{ case = "a"; arm = "tandem"; rate = 67 }, [pscustomobject]@{ case = "a"; arm = "baseline"; rate = 33 }, [pscustomobject]@{ case = "b"; rate = 50 }))
    Check "Get-Lift: one case in both arms, +34" ($lift.Count -eq 1 -and $lift[0].lift -eq 34)
}
finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }

# ---- Invoke-Evals end to end with a fake opencode

if ($IsWindows -or $env:OS -eq "Windows_NT") { Write-Output "skip end to end (needs bash)" }
else {
    $tmp = New-TempDir "harness-run"
    try {
        $env:FAKE_LOG = Join-Path $tmp "calls.log"
        $env:FAKE_CORRECT = Join-Path $PSScriptRoot "fixtures/repo/L1-correct"
        $out = Join-Path $tmp "results"
        $fake = Join-Path $PSScriptRoot "selftest/fake-opencode"
        $text = & (Join-Path $PSScriptRoot "Invoke-Evals.ps1") -Case feature-outcome -Arm both -Runs 2 -Opencode $fake -NoExec -OutDir $out -WarningAction SilentlyContinue 2>&1 | Out-String
        $file = @(Get-ChildItem -LiteralPath $out -Filter *.json)
        Check "a results file was written" ($file.Count -eq 1) $text
        if ($file.Count -eq 1) {
            $r = Get-Content -Raw $file[0].FullName | ConvertFrom-Json
            $t = @($r.cases | Where-Object { $_.arm -eq "tandem" })[0]
            $b = @($r.cases | Where-Object { $_.arm -eq "baseline" })[0]
            Check "results are version 4 with both arms" ($r.version -eq 4 -and (@($r.arms) -join ",") -eq "tandem,baseline")
            Check "Tandem runs add up 3 opencode calls: 450 tokens, 0.03 cost, 1 question, 1 failed verify" ($t.runs[0].tokens -eq 450 -and [math]::Abs($t.runs[0].cost - 0.03) -lt 0.0001 -and $t.runs[0].questions -eq 1 -and $t.runs[0].verifyFails -eq 1 -and $t.runs[0].usageKnown) "tokens=$($t.runs[0].tokens) cost=$($t.runs[0].cost) q=$($t.runs[0].questions) vf=$($t.runs[0].verifyFails)"
            Check "Tandem case: mean and per-pass tokens, prompt tokens counted" ($t.meanTokens -eq 450 -and $t.tokensPerPass -eq 450 -and $t.meanQuestions -eq 1 -and $t.promptTokens -gt 0)
            Check "baseline case: 400 tokens a run, no per-pass number without a pass, no prompt tokens" ($b.meanTokens -eq 400 -and $null -eq $b.tokensPerPass -and $b.promptTokens -eq 0)
            Check "Tandem entry records its model and files hash; baseline has none" ($t.model -eq "opencode default" -and $t.filesHash -match '^[0-9a-f]{12}$' -and $null -eq $b.filesHash -and $r.kind -eq "lift")
            Check "each step has its own tokens" ($t.runs[0].steps[0].tokens -eq 150 -and $t.runs[0].steps[1].tokens -eq 0)
            Check "Tandem arm passed 2 of 2 (steps ran in order, gates approved)" ($t.passes -eq 2 -and $t.passAll) (($t.runs | ForEach-Object { $_.failed | ForEach-Object { $_.check } }) -join "; ")
            Check "Tandem arm recorded 4 steps, do-task once per task" (@($t.runs[0].steps).Count -eq 4 -and $t.runs[0].steps[3].runs -eq 2)
            Check "baseline arm failed 2 of 2 (inline rate)" ($b.passes -eq 0 -and $b.rate -eq 0)
            Check "summary shows the lift" ($text -match '\| feature-outcome \| opencode default \| 100% \| 0% \| \+100 \|') $text
        }
        $calls = @(Get-Content -LiteralPath $env:FAKE_LOG)
        $plain = @($calls | Where-Object { $_ -notmatch ' --command ' })
        $tandemCalls = @($calls | Where-Object { $_ -match ' --command ' })
        Check "every call asked for JSON events" (@($calls | Where-Object { $_ -notmatch '--format json' }).Count -eq 0)
        Check "baseline ran twice, with its own config folder" ($plain.Count -eq 2 -and @($plain | Where-Object { $_ -match 'xdg=\S+' }).Count -eq 2)
        Check "Tandem arm ran with your normal config" (@($tandemCalls | Where-Object { $_ -match 'xdg=\S' -and $_ -match 'eval-plain-config' }).Count -eq 0)

        # -Affected: nothing changed since that run
        $inv = Join-Path $PSScriptRoot "Invoke-Evals.ps1"
        $aff = & $inv -Case feature-outcome -Affected -Opencode $fake -NoExec -OutDir $out -WarningAction SilentlyContinue 2>&1 | Out-String
        Check "-Affected runs nothing when prompts did not change" ($aff -match 'Nothing changed' -and @(Get-ChildItem -LiteralPath $out -Filter *.json).Count -eq 1) $aff

        # -MaxRuns refuses before anything starts
        $cap = try { & $inv -Case feature-outcome -Arm both -Runs 3 -MaxRuns 5 -Opencode $fake -NoExec -OutDir $out -WarningAction SilentlyContinue 2>&1 | Out-String } catch { $_.Exception.Message }
        Check "-MaxRuns refuses 6 runs over a cap of 5" ($cap -match 'would start 6 model runs' -and @(Get-ChildItem -LiteralPath $out -Filter *.json).Count -eq 1) $cap

        # -Models: every case on each model
        Start-Sleep -Milliseconds 1100
        $mm = & $inv -Case feature-outcome -Models "p/one,p/two" -Runs 1 -Opencode $fake -NoExec -OutDir $out -WarningAction SilentlyContinue 2>&1 | Out-String
        $mf = @(Get-ChildItem -LiteralPath $out -Filter *.json | Sort-Object LastWriteTime)[-1]
        $mj = Get-Content -Raw $mf.FullName | ConvertFrom-Json
        Check "-Models runs each model and records it" ((@($mj.models) -join ",") -eq "p/one,p/two" -and (@($mj.cases | ForEach-Object { $_.model }) -join ",") -eq "p/one,p/two") $mm
        Check "-Models passes --model to opencode" (@(Get-Content -LiteralPath $env:FAKE_LOG | Where-Object { $_ -match '--model p/two' }).Count -gt 0)

        # -Gate: a drop against the newest results exits 1
        Start-Sleep -Milliseconds 1100
        $env:FAKE_BREAK = "1"
        $null = & $inv -Case feature-outcome -Runs 1 -Gate -Opencode $fake -NoExec -OutDir $out -Model "p/one" -WarningAction SilentlyContinue 2>&1 | Out-String
        Check "-Gate exits 1 when a Tandem case dropped" ($LASTEXITCODE -eq 1)
        Remove-Item Env:FAKE_BREAK -ErrorAction SilentlyContinue

        # -Overlay: the tandem arm runs a scratch install; your real config is not used
        Start-Sleep -Milliseconds 1100
        $ov = Join-Path $tmp "overlay/commands"; New-Item -ItemType Directory -Path $ov -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot "core/commands/spec.md") -Destination $ov
        Add-Content -LiteralPath (Join-Path $ov "spec.md") -Value "`nExperiment line."
        $before = @(Get-Content -LiteralPath $env:FAKE_LOG).Count
        $ex = & $inv -Case feature-outcome -Runs 1 -Overlay (Join-Path $tmp "overlay") -Label "exp-1" -Opencode $fake -NoExec -OutDir $out -WarningAction SilentlyContinue 2>&1 | Out-String
        $ef = @(Get-ChildItem -LiteralPath $out -Filter *.json | Sort-Object LastWriteTime)[-1]
        $ej = Get-Content -Raw $ef.FullName | ConvertFrom-Json
        $exCalls = @(Get-Content -LiteralPath $env:FAKE_LOG | Select-Object -Skip $before)
        Check "-Overlay runs the tandem arm on a scratch install" ($exCalls.Count -gt 0 -and @($exCalls | Where-Object { $_ -notmatch 'eval-experiment-config' }).Count -eq 0) ($ex + ($exCalls -join "`n"))
        Check "an experiment is labelled and its files hash differs" ($ej.kind -eq "experiment" -and $ej.label -eq "exp-1" -and $ej.cases[0].filesHash -ne $t.filesHash)
        Check "an experiment compares with the newest non-experiment file" ($ej.compareTo -and $ej.compareTo -ne $ef.Name)

        # The writing judge (fake: yes to everything) and Test-Expect wiring
        $env:EVAL_JUDGE_MODEL = "p/judge"; $env:EVAL_OPENCODE = $fake
        $jr = @(Invoke-Judge -Rubric spike -Text "# Spike findings`n")
        Check "Invoke-Judge asks every rubric question and passes at 5 of 5" ($jr.Count -eq 6 -and $jr[-1].Pass -and $jr[-1].Check -match '5 of 5') (($jr | ForEach-Object { $_.Check }) -join " | ")
        Remove-Item Env:EVAL_JUDGE_MODEL, Env:EVAL_OPENCODE -ErrorAction SilentlyContinue

        # Improve loop: trim and fix experiments, a run that records itself, keep and drop
        $expRoot = Join-Path $PSScriptRoot "experiments"
        $beforeIds = @(if (Test-Path $expRoot) { Get-ChildItem -LiteralPath $expRoot -Directory | ForEach-Object { $_.Name } })
        try {
            $trim = & (Join-Path $PSScriptRoot "Suggest-Trim.ps1") -Command spec -Max 2 2>&1 | Out-String
            $ids = @(Get-ChildItem -LiteralPath $expRoot -Directory | Where-Object { $beforeIds -notcontains $_.Name } | ForEach-Object { $_.Name })
            Check "Suggest-Trim makes one experiment per section (2)" ($ids.Count -eq 2 -and @($ids | Where-Object { $_ -like "trim-spec-*" }).Count -eq 2) $trim
            $one = Join-Path $expRoot "$($ids[0])/overlay/commands/spec.md"
            Check "a trim experiment is shorter than the command" ((Get-Item $one).Length -lt (Get-Item (Join-Path $script:RepoRoot "core/commands/spec.md")).Length)

            $resFile = @(Get-ChildItem -LiteralPath $out -Filter *.json | Sort-Object LastWriteTime | Where-Object { (Get-Content -Raw $_.FullName | ConvertFrom-Json).cases | Where-Object { $_.case -eq "feature-outcome" -and $_.arm -eq "tandem" -and -not $_.passAll } } | Select-Object -Last 1)
            $fix = & (Join-Path $PSScriptRoot "Suggest-Fix.ps1") -Results $resFile[0].FullName -Case feature-outcome -Model p/suggest -Opencode $fake -File commands/spec.md 2>&1 | Out-String
            $fixId = @(Get-ChildItem -LiteralPath $expRoot -Directory | Where-Object { $_.Name -like "fix-spec-*" -and $beforeIds -notcontains $_.Name } | ForEach-Object { $_.Name })[0]
            Check "Suggest-Fix saves the model's edit as an experiment" ($fixId -and ([IO.File]::ReadAllText((Join-Path $expRoot "$fixId/overlay/commands/spec.md")) -match '\(clearer\)')) $fix

            $null = & $inv -Case feature-outcome -Runs 1 -Overlay (Join-Path $expRoot "$fixId/overlay") -Label $fixId -Opencode $fake -NoExec -OutDir $out -WarningAction SilentlyContinue 2>&1 | Out-String
            $meta = Get-Content -Raw (Join-Path $expRoot "$fixId/experiment.json") | ConvertFrom-Json
            Check "an experiment run is listed in experiment.json" (@($meta.results).Count -eq 1)

            $dropOut = & (Join-Path $PSScriptRoot "Keep-Experiment.ps1") -Id $ids[1] -Drop 2>&1 | Out-String
            Check "Keep-Experiment -Drop marks it dropped" ((Get-Content -Raw (Join-Path $expRoot "$($ids[1])/experiment.json") | ConvertFrom-Json).status -eq "dropped") $dropOut
        }
        finally {
            foreach ($d in @(if (Test-Path $expRoot) { Get-ChildItem -LiteralPath $expRoot -Directory | Where-Object { $beforeIds -notcontains $_.Name } })) { Remove-Item -LiteralPath $d.FullName -Recurse -Force }
        }
    }
    finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item Env:FAKE_LOG, Env:FAKE_CORRECT, Env:FAKE_BREAK -ErrorAction SilentlyContinue
    }
}

if ($failed) { Write-Output "$failed check(s) failed."; exit 1 }
Write-Output "Eval harness: all checks passed."
exit 0
