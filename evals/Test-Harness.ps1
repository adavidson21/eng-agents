<#
.SYNOPSIS
  Checks Invoke-Evals.ps1 itself with a fake opencode (no model, no dotnet): the Tandem arm runs a case's steps in
  order and approves gates between them, the baseline arm runs the plain prompt with Tandem's rules out of the config
  folder, and the results file holds both arms and the lift. Run in CI on Linux; needs bash.
  Run: pwsh -NoProfile -File evals/Test-Harness.ps1
#>
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib/EvalLib.ps1")

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
            Check "results are version 3 with both arms" ($r.version -eq 3 -and (@($r.arms) -join ",") -eq "tandem,baseline")
            Check "Tandem runs add up 5 opencode calls: 750 tokens, 0.05 cost, 1 question, 1 failed verify" ($t.runs[0].tokens -eq 750 -and [math]::Abs($t.runs[0].cost - 0.05) -lt 0.0001 -and $t.runs[0].questions -eq 1 -and $t.runs[0].verifyFails -eq 1 -and $t.runs[0].usageKnown) "tokens=$($t.runs[0].tokens) cost=$($t.runs[0].cost) q=$($t.runs[0].questions) vf=$($t.runs[0].verifyFails)"
            Check "Tandem case: mean and per-pass tokens, prompt tokens counted" ($t.meanTokens -eq 750 -and $t.tokensPerPass -eq 750 -and $t.meanQuestions -eq 1 -and $t.promptTokens -gt 0)
            Check "baseline case: 400 tokens a run, no per-pass number without a pass, no prompt tokens" ($b.meanTokens -eq 400 -and $null -eq $b.tokensPerPass -and $b.promptTokens -eq 0)
            Check "each step has its own tokens" ($t.runs[0].steps[0].tokens -eq 150 -and $t.runs[0].steps[1].tokens -eq 0)
            Check "Tandem arm passed 2 of 2 (steps ran in order, gates approved)" ($t.passes -eq 2 -and $t.passAll) (($t.runs | ForEach-Object { $_.failed | ForEach-Object { $_.check } }) -join "; ")
            Check "Tandem arm recorded 6 steps, do-task once per task" (@($t.runs[0].steps).Count -eq 6 -and $t.runs[0].steps[5].runs -eq 2)
            Check "baseline arm failed 2 of 2 (inline rate)" ($b.passes -eq 0 -and $b.rate -eq 0)
            Check "summary shows the lift" ($text -match '\| feature-outcome \| 100% \| 0% \| \+100 \|') $text
        }
        $calls = @(Get-Content -LiteralPath $env:FAKE_LOG)
        $plain = @($calls | Where-Object { $_ -notmatch ' --command ' })
        $tandemCalls = @($calls | Where-Object { $_ -match ' --command ' })
        Check "every call asked for JSON events" (@($calls | Where-Object { $_ -notmatch '--format json' }).Count -eq 0)
        Check "baseline ran twice, with its own config folder" ($plain.Count -eq 2 -and @($plain | Where-Object { $_ -match 'xdg=\S+' }).Count -eq 2)
        Check "Tandem arm ran with your normal config" (@($tandemCalls | Where-Object { $_ -match 'xdg=\S' -and $_ -match 'eval-plain-config' }).Count -eq 0)
    }
    finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item Env:FAKE_LOG, Env:FAKE_CORRECT -ErrorAction SilentlyContinue
    }
}

if ($failed) { Write-Output "$failed check(s) failed."; exit 1 }
Write-Output "Eval harness: all checks passed."
exit 0
