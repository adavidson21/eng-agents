<#
.SYNOPSIS
  Self-test for Export-Backlog.ps1 -Check, -Csv and -Local. Uses a temp folder and config; calls no ADO.
  Run: pwsh -NoProfile -File core/scripts/ado/Test-ExportBacklog.ps1   (also works in Windows PowerShell 5.1)
#>
$ErrorActionPreference = "Stop"

$failed = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = "") {
    if ($Ok) { Write-Output "ok   $Name" } else { Write-Output "FAIL $Name $Detail"; $script:failed++ }
}

$ps = (Get-Process -Id $PID).Path
$export = Join-Path $PSScriptRoot "Export-Backlog.ps1"
function Run([string[]]$Arguments) {
    $ErrorActionPreference = "Continue"   # Windows PowerShell 5.1 turns a child's stderr into errors
    $out = & $ps -NoProfile -ExecutionPolicy Bypass -File $export @Arguments 2>&1 | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}
function Write-Text([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false))) }

$good = @'
# Milestones: test

Status: APPROVED

Epic: Orders v2.1

Lets customers track orders.

## Feature 1: Order history

Customers can see their past orders in one place, so they stop calling support to ask.

#### Release note

You can now see all of your past orders on one page.

### Story 1.1: List past orders

As a customer, I want to see my past orders, so that I can find one quickly.

#### Acceptance criteria

```gherkin
Scenario: Orders are listed
  Given I have placed orders
  When I open my order history
  Then I see my orders, newest first
```

#### Notes for the builder

- Where to look: `orders-api/src/OrdersController.cs`

## Open questions

- None.
'@

$root = Join-Path ([IO.Path]::GetTempPath()) ("eb-" + [guid]::NewGuid().ToString("N"))
$work = Join-Path $root ".work"
$scope = Join-Path $work "scope-test"
New-Item -ItemType Directory -Path $scope -Force | Out-Null
$milestones = Join-Path $scope "milestones.md"
$config = Join-Path $root "config.json"
try {
    Write-Text $milestones $good
    $r = Run @("-Folder", $scope, "-Check")
    Check "check passes" ($r.Code -eq 0 -and $r.Out -match "OK: Epic: Orders v2.1; 1 feature") $r.Out

    $r = Run @("-Folder", $scope, "-Csv", "-ConfigPath", (Join-Path $root "missing.json"))
    $csv = [IO.File]::ReadAllText((Join-Path $scope "backlog.csv"))
    Check "csv without config: release notes left out, with a note" ($r.Code -eq 0 -and $r.Out -match "releaseNoteColumn" -and $csv -notmatch "Release Notes") "$($r.Out) $csv"

    Write-Text $config '{ "releaseNoteColumn": "Release Notes" }'
    $r = Run @("-Folder", $scope, "-Csv", "-ConfigPath", $config)
    $rows = @(Import-Csv (Join-Path $scope "backlog.csv"))
    $feature = $rows | Where-Object { $_."Work Item Type" -eq "Feature" }
    $story = $rows | Where-Object { $_."Work Item Type" -eq "User Story" }
    Check "csv: feature release note in its own column" ($r.Code -eq 0 -and $feature."Release Notes" -eq "You can now see all of your past orders on one page.") "$($r.Out)"
    Check "csv: feature description is the short paragraph" ($feature.Description -match "stop calling support" -and $feature.Description -notmatch "Release note") $feature.Description
    Check "csv: story leaves out builder notes" ($story.Description -match "As a customer" -and $story.Description -notmatch "OrdersController|Notes for the builder|Part of") $story.Description

    $r = Run @("-Folder", $scope, "-Local", "-ConfigPath", $config)
    $item = Get-ChildItem $work -Directory | Where-Object { $_.Name -like "L*" } | Select-Object -First 1
    $wi = if ($item) { [IO.File]::ReadAllText((Join-Path $item.FullName "workitem.md")) } else { "" }
    Check "local: story keeps builder notes" ($r.Code -eq 0 -and $wi -match "OrdersController" -and $wi -match "Part of") "$($r.Out) $wi"

    Write-Text $milestones ($good -replace "(?s)#### Release note\s+You can now[^\n]*\n", "")
    $r = Run @("-Folder", $scope, "-Check")
    Check "check: missing release note fails" ($r.Code -eq 1 -and $r.Out -match "FORMAT: Feature 1 has no '#### Release note'") $r.Out

    Write-Text $milestones ($good -replace "You can now see all of your past orders on one page\.", ("Long. " * 60))
    $r = Run @("-Folder", $scope, "-Check")
    Check "check: long release note fails" ($r.Code -eq 1 -and $r.Out -match "release note is \d+ characters") $r.Out

    Write-Text $milestones ($good -replace "Customers can see their past orders in one place, so they stop calling support to ask\.", "<Two or three sentences.>")
    $r = Run @("-Folder", $scope, "-Check")
    Check "check: placeholder description fails" ($r.Code -eq 1 -and $r.Out -match "Feature 1 description still has a template placeholder") $r.Out

    Write-Text $milestones ($good -replace "#### Notes for the builder", "#### Work item")
    $r = Run @("-Folder", $scope, "-Check")
    Check "check: older 'Work item' heading still reads" ($r.Code -eq 0) $r.Out
}
finally {
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failed) { Write-Output "$failed check(s) failed."; exit 1 }
Write-Output "All Export-Backlog checks passed."
