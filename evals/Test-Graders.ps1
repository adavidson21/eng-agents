<#
.SYNOPSIS
  Checks the eval graders themselves, with no model and no dotnet: for every case, a hand-written good
  output must pass its grader and a hand-written bad output must fail it. Run in CI.
  Run: pwsh -NoProfile -File evals/Test-Graders.ps1   (also works in Windows PowerShell 5.1)

.DESCRIPTION
  Golden outputs live in evals/goldens/<case>/pass and evals/goldens/<case>/fail:
    work/         files dropped into .work/ (progress-add.md is appended to progress.md)
    repo/         files copied into sample-api and committed as one commit (what an agent commit leaves)
    uncommitted/  files copied into sample-api and left uncommitted
  A gate file line "Draft-hash: STAMP" is replaced with the real hash, as Set-DraftHash.ps1 would.
#>
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib/EvalLib.ps1")
. (Join-Path $PSScriptRoot "lib/Graders.ps1")

$failed = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = "") {
    if ($Ok) { Write-Output "ok   $Name" } else { Write-Output "FAIL $Name $Detail"; $script:failed++ }
}

function Set-Stamps([string]$Root) {
    $work = Join-Path $Root ".work"
    if (-not (Test-Path -LiteralPath $work)) { return }
    foreach ($f in (Get-ChildItem -LiteralPath $work -Recurse -File -Filter *.md)) {
        $t = [IO.File]::ReadAllText($f.FullName)
        if ($t -notmatch '(?m)^Draft-hash: STAMP\s*$') { continue }
        $t = [regex]::Replace($t, '(?m)^Draft-hash: STAMP', ("Draft-hash: " + (Get-DraftHash -Text $t)))
        [IO.File]::WriteAllText($f.FullName, $t, $script:Utf8)
    }
}

$cases = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot "cases") -Filter *.json | Sort-Object Name
Check "found eval cases" ($cases.Count -ge 8) "found $($cases.Count)"

foreach ($cf in $cases) {
    $case = Read-Case $cf.FullName
    $name = $cf.BaseName
    Check "$name has a grader function" ([bool](Get-Command $case.grader -ErrorAction SilentlyContinue)) $case.grader
    foreach ($kind in @("pass", "fail")) {
        $golden = Join-Path $PSScriptRoot "goldens/$name/$kind"
        if (-not (Test-Path -LiteralPath $golden)) { Check "$name has a $kind golden" $false; continue }
        $root = New-TempDir "graders"
        try {
            $ws = New-EvalWorkspace $case $root
            Set-GoldenOutput $ws $golden
            Set-Stamps $root
            $checks = @(& $case.grader $ws -NoExec)
            $bad = @($checks | Where-Object { -not $_.Pass })
            if ($kind -eq "pass") {
                Check "$name good output passes ($($checks.Count) checks)" ($checks.Count -gt 0 -and $bad.Count -eq 0) ("`n      " + (@($bad | ForEach-Object { "$($_.Check): $($_.Detail)" }) -join "`n      "))
            }
            else {
                Check "$name bad output fails ($($bad.Count) of $($checks.Count) checks fail)" ($bad.Count -gt 0)
            }
        }
        finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# The fixture workspace itself must not trip a "no changes" grader.
$root = New-TempDir "graders"
try {
    $ws = New-EvalWorkspace (Read-Case (Join-Path $PSScriptRoot "cases/spec-basic.json")) $root
    $c = New-Checks; Test-RepoUntouched $ws $c
    Check "fresh workspace counts as untouched" ($c[0].Pass) $c[0].Detail
}
finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }

if ($failed) { Write-Output "$failed check(s) failed."; exit 1 }
Write-Output "Eval graders: all checks passed."
