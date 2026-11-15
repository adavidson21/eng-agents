<#
.SYNOPSIS
  Checks the eval fixtures behave as the cases assume. Needs dotnet (8 or later); no model. Run in CI.
  Run: pwsh -NoProfile -File evals/Test-Fixtures.ps1

.DESCRIPTION
  - The fixture workspace builds and its tests pass (the baseline in the work fixtures says PASS).
  - The correct implementation (fixtures/repo/L1-correct) passes its own tests and the hidden acceptance tests.
  - The planted bug (fixtures/repo/L1-planted) passes its own tests but fails the hidden ones, so only a
    careful review can catch it.
  - The bug in work item L2 is real: an order with no lines throws.
  - The do-task grader passes the golden good output with dotnet running.
#>
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib/EvalLib.ps1")
. (Join-Path $PSScriptRoot "lib/Graders.ps1")

$failed = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = "") {
    if ($Ok) { Write-Output "ok   $Name" } else { Write-Output "FAIL $Name $Detail"; $script:failed++ }
}
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { Write-Output "dotnet not found"; exit 1 }

function Invoke-Test([string]$Root, [string]$Filter) {
    Push-Location $Root
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    $a = @("test", "sample-api/tests/Orders.Tests/Orders.Tests.csproj", "--nologo")
    if ($Filter) { $a += @("--filter", $Filter) }
    $out = & dotnet @a 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    Pop-Location
    return [pscustomobject]@{ Ok = ($code -eq 0); Out = (($out -split "\r?\n" | Select-Object -Last 8) -join " / ") }
}

$hidden = Join-Path $PSScriptRoot "fixtures/hidden/BulkDiscountAcceptanceTests.cs"
$spec = Read-Case (Join-Path $PSScriptRoot "cases/spec-basic.json")

$root = New-TempDir "fixtures"
try {
    $ws = New-EvalWorkspace $spec $root
    $r = Invoke-Test $root
    Check "fixture workspace: tests pass" $r.Ok $r.Out

    $probe = Join-Path $ws.Repo "tests/Orders.Tests/NoLinesProbe.cs"
    [IO.File]::WriteAllText($probe, "using Orders;`nnamespace Orders.Tests;`npublic class NoLinesProbe { [Fact] public void Probe() { Assert.Equal(0m, OrderTotals.Calculate(new Order { Id = `"p`" })); } }`n", $script:Utf8)
    $r = Invoke-Test $root "FullyQualifiedName~NoLinesProbe"
    Check "L2 bug is real: an order with no lines does not total 0" (-not $r.Ok) $r.Out
    Remove-Item -LiteralPath $probe -Force
}
finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }

foreach ($v in @("correct", "planted")) {
    $root = New-TempDir "fixtures"
    try {
        $ws = New-EvalWorkspace $spec $root
        Copy-Overlay (Join-Path $PSScriptRoot "fixtures/repo/L1-$v") $ws.Repo
        $r = Invoke-Test $root
        Check "L1-${v}: its own tests pass" $r.Ok $r.Out
        Copy-Item -LiteralPath $hidden -Destination (Join-Path $ws.Repo "tests/Orders.Tests") -Force
        $r = Invoke-Test $root "FullyQualifiedName~BulkDiscountAcceptanceTests"
        if ($v -eq "correct") { Check "L1-correct: hidden acceptance tests pass" $r.Ok $r.Out }
        else { Check "L1-planted: hidden acceptance tests fail (the bug is real)" (-not $r.Ok) $r.Out }
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

$root = New-TempDir "fixtures"
try {
    $case = Read-Case (Join-Path $PSScriptRoot "cases/do-task.json")
    $ws = New-EvalWorkspace $case $root
    Set-GoldenOutput $ws (Join-Path $PSScriptRoot "goldens/do-task/pass")
    $checks = @(Test-DoTask $ws)
    $bad = @($checks | Where-Object { -not $_.Pass })
    Check "do-task grader with dotnet: good output passes" ($bad.Count -eq 0) (@($bad | ForEach-Object { "$($_.Check): $($_.Detail)" }) -join " | ")
    Check "do-task grader removed the hidden test again" (-not (Test-Path (Join-Path $ws.Repo "tests/Orders.Tests/BulkDiscountAcceptanceTests.cs")))
}
finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }

if ($failed) { Write-Output "$failed check(s) failed."; exit 1 }
Write-Output "Eval fixtures: all checks passed."
