<#
.SYNOPSIS
    Suggest one prompt fix from failed runs: reads a results file, collects one case's failed checks and failed
    steps (tandem arm), and asks a model (-Model, any provider/model, free or paid, with Tandem left out) for one
    small edit to the command or agent most likely at fault. Saves it as an experiment (evals/experiments/<id>/),
    never touching core/. Test it with Invoke-Evals -Overlay, keep it with Keep-Experiment.ps1.

.EXAMPLE
    ./evals/Suggest-Fix.ps1 -Results evals/results/4.1.0-20261115-101500.json -Case spec-basic -Model opencode/some-model
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Results,
    [Parameter(Mandatory)][string]$Case,
    [Parameter(Mandatory)][string]$Model,
    [string]$Opencode = "opencode",
    # Which file to change, relative to core/ (default: the command of the first failed step, else the case's command).
    [string]$File
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib/EvalLib.ps1")
. (Join-Path $PSScriptRoot "lib/Experiments.ps1")
if ($Case -notmatch '^[a-z0-9][a-z0-9-]*$') { throw "Bad case name: $Case" }
$doc = Get-Content -Raw -LiteralPath $Results | ConvertFrom-Json
$entry = @($doc.cases | Where-Object { $_.case -eq $Case -and (-not $_.arm -or $_.arm -eq "tandem") })[0]
if (-not $entry) { throw "No tandem results for $Case in $Results" }
$fails = @($entry.runs | Where-Object { -not $_.pass })
if (-not $fails.Count) { Write-Output "$Case passed every run in $(Split-Path $Results -Leaf): nothing to fix."; exit 0 }
$caseObj = Read-Case (Join-Path $PSScriptRoot "cases/$Case.json")
$cmds = @(Get-CaseCommands $caseObj)
if (-not $File) {
    $failedStep = @($fails | ForEach-Object { @($_.steps) } | Where-Object { -not $_.ok -and $_.step -match '^/([a-z-]+)' } | Select-Object -First 1)
    $cmd = if ($failedStep.Count) { ([regex]::Match($failedStep[0].step, '^/([a-z-]+)')).Groups[1].Value } elseif ($cmds.Count) { $cmds[-1] } else { $null }
    if (-not $cmd) { throw "Could not tell which command to fix; pass -File commands/<name>.md" }
    $File = "commands/$cmd.md"
}
$cmdName = [IO.Path]::GetFileNameWithoutExtension($File)
$full = Join-Path $script:RepoRoot "core/$File"
if (-not (Test-Path -LiteralPath $full)) { throw "Not found: core/$File" }
$text = [IO.File]::ReadAllText($full)
$evidence = ($fails | Select-Object -First 5 | ForEach-Object {
    $r = $_
    "Run $($r.run):`n" + (@($r.failed | ForEach-Object { "- failed check: $($_.check)$(if ($_.detail) { " ($($_.detail))" })" }) -join "`n") + "`n" +
    (@($r.steps | Where-Object { -not $_.ok } | ForEach-Object { "- failed step: $($_.step)" }) -join "`n")
}) -join "`n"
$prompt = @"
You improve prompts for coding agents. One prompt file failed some evaluation runs. Propose ONE small, specific edit
to the file that would most likely fix the failures without making the file longer than needed. Do not rewrite it.

Case: $Case ($($caseObj.description))
Failures:
$evidence

The file (core/$File):
<<<
$text
>>>

Reply with JSON only: {"find": "exact text from the file, a full line or more", "replace": "the new text", "reason": "one sentence"}
"@
$oc = Get-Command $Opencode -ErrorAction Stop
$home2 = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$xdg = New-TempDir "eval-suggest-config"
$jd = Join-Path $xdg "opencode"; New-Item -ItemType Directory -Path $jd -Force | Out-Null
$pc = New-PlainOpencodeConfig -UserDir $(if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME "opencode" } else { Join-Path $home2 ".config/opencode" })
[IO.File]::WriteAllText((Join-Path $jd $pc.Name), $pc.Text, $script:Utf8)
$old = $env:XDG_CONFIG_HOME
try { $env:XDG_CONFIG_HOME = $xdg; $raw = & $oc.Source run --model $Model --format json $prompt 2>$null | Out-String }
finally { $env:XDG_CONFIG_HOME = $old; Remove-Item -LiteralPath $xdg -Recurse -Force -ErrorAction SilentlyContinue }
$answer = (($raw -split "\r?\n") | ForEach-Object { try { $ev = $_ | ConvertFrom-Json; if ($ev.type -eq "text" -and $ev.part.text) { $ev.part.text } } catch { } }) -join ""
if (-not $answer) { $answer = $raw }
$json = [regex]::Match($answer, '(?s)\{.*"find".*\}').Value
try { $s = $json | ConvertFrom-Json } catch { throw "The model did not answer with the JSON asked for. Its answer: $($answer.Substring(0, [math]::Min(400, $answer.Length)))" }
$count = ([regex]::Matches($text, [regex]::Escape("$($s.find)"))).Count
if ($count -ne 1) { throw "The suggested edit's find text appears $count times in core/$File (it must appear once). Run again, or edit by hand." }
$new = $text.Replace("$($s.find)", "$($s.replace)")
$e = Save-Experiment -Kind "fix" -Command $cmdName -File $File -NewText $new -Reason "$($s.reason)" -Case $Case
Write-Output "Experiment $($e.Id): $($s.reason)"
Write-Output "Test it: ./evals/Invoke-Evals.ps1 -Case $Case -Overlay $($e.Overlay) -Label $($e.Id) -Model <the model you test with>"
exit 0
