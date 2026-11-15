<#
.SYNOPSIS
    Checks the writing judge's rubrics. With no model (CI): every rubric has 3 to 8 yes/no questions, a pass bar,
    and a good.md and bad.md example; every case that names a rubric names one that exists. With -Model: the judge
    must pass good.md and fail bad.md for every rubric (calibration), before its scores are trusted for that model.

.EXAMPLE
    ./evals/Test-Judge.ps1
.EXAMPLE
    ./evals/Test-Judge.ps1 -Model opencode/some-free-model
#>
[CmdletBinding()]
param([string]$Model, [string]$Opencode = "opencode", [string[]]$Rubric)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib/EvalLib.ps1")
. (Join-Path $PSScriptRoot "lib/Graders.ps1")
$failed = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = "") {
    if ($Ok) { Write-Output "ok   $Name" } else { Write-Output "FAIL $Name $Detail"; $script:failed++ }
}
$dir = Join-Path $PSScriptRoot "rubrics"
$rubrics = @(Get-ChildItem -LiteralPath $dir -Filter *.json | Sort-Object Name)
if ($Rubric) { $rubrics = @($rubrics | Where-Object { $Rubric -contains $_.BaseName }) }
foreach ($f in $rubrics) {
    $r = Get-Content -Raw -LiteralPath $f.FullName | ConvertFrom-Json
    $n = $f.BaseName
    $q = @($r.questions)
    Check "$n has 3 to 8 questions" ($q.Count -ge 3 -and $q.Count -le 8) "$($q.Count)"
    Check "$n has a pass bar between 0.5 and 1" ($r.pass -ge 0.5 -and $r.pass -le 1)
    Check "$n has good.md and bad.md" ((Test-Path (Join-Path $dir "$n/good.md")) -and (Test-Path (Join-Path $dir "$n/bad.md")))
}
foreach ($cf in (Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot "cases") -Filter *.json)) {
    $c = Read-Case $cf.FullName
    if ($c.expect -and $c.expect.judge) { Check "$($cf.BaseName) names a rubric that exists" (Test-Path (Join-Path $dir "$($c.expect.judge.rubric).json")) $c.expect.judge.rubric }
}
if ($Model) {
    $oc = Get-Command $Opencode -ErrorAction Stop
    $env:EVAL_JUDGE_MODEL = $Model
    $env:EVAL_OPENCODE = $oc.Source
    $xdg = New-TempDir "eval-judge-config"
    $jd = Join-Path $xdg "opencode"; New-Item -ItemType Directory -Path $jd -Force | Out-Null
    $home2 = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    $pc = New-PlainOpencodeConfig -UserDir $(if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME "opencode" } else { Join-Path $home2 ".config/opencode" })
    [IO.File]::WriteAllText((Join-Path $jd $pc.Name), $pc.Text, $script:Utf8)
    $env:EVAL_PLAIN_CONFIG = $xdg
    try {
        foreach ($f in $rubrics) {
            $n = $f.BaseName
            foreach ($kind in @("good", "bad")) {
                $res = @(Invoke-Judge -Rubric $n -Text ([IO.File]::ReadAllText((Join-Path $dir "$n/$kind.md"))))
                $verdict = $res[-1]
                foreach ($x in $res) { Write-Output "     $($x.Check)" }
                if ($kind -eq "good") { Check "judge passes $n/good.md" $verdict.Pass $verdict.Detail } else { Check "judge fails $n/bad.md" (-not $verdict.Pass) $verdict.Detail }
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $xdg -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item Env:EVAL_JUDGE_MODEL, Env:EVAL_OPENCODE, Env:EVAL_PLAIN_CONFIG -ErrorAction SilentlyContinue
    }
}
if ($failed) { Write-Output "$failed check(s) failed."; exit 1 }
Write-Output "Judge rubrics: all checks passed$(if ($Model) { " (calibrated on $Model)" })."
exit 0
