<#
.SYNOPSIS
    Checks this repo's .work parser (New-Dashboard.ps1) against Workshop's .work contract.

.DESCRIPTION
    Tandem writes .work; Workshop's Dispatch reads it with its own parser (connectors/opencode/lib/workparser.mjs).
    The two meet only at the .work format: Workshop's docs/work-format.md, with a synthetic example workspace
    (docs/examples/work/) and what the format's rules read from it (expected.json). This script copies that
    example into a temporary folder (every file with the same modification time, as expected.json assumes),
    runs New-Dashboard.ps1 -AsJson on it, and compares each item's fields with expected.json. A change to how
    Tandem writes .work that Workshop would read differently fails here.

    CI checks out Workshop next to this repo. Locally: git clone https://github.com/adavidson21/workshop, then
    ./core/scripts/dashboard/Test-WorkFormat.ps1 -Workshop ../workshop

.PARAMETER Workshop
    A checkout of adavidson21/workshop.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Workshop
)
$ErrorActionPreference = 'Stop'

$example = Join-Path $Workshop 'docs/examples/work'
$expectedFile = Join-Path $example 'expected.json'
if (-not (Test-Path -LiteralPath $expectedFile)) { throw "No $expectedFile. Is $Workshop a Workshop checkout?" }

$root = Join-Path ([IO.Path]::GetTempPath()) ("work-format-" + [guid]::NewGuid().ToString('N'))
$work = Join-Path $root '.work'
try {
    New-Item -ItemType Directory -Path $root | Out-Null
    Copy-Item -LiteralPath $example -Destination $work -Recurse
    Remove-Item -LiteralPath (Join-Path $work 'expected.json')
    $dash = Join-Path $work '_dashboard'
    if (Test-Path -LiteralPath $dash) { Remove-Item -LiteralPath $dash -Recurse -Force }
    $when = [datetime]::SpecifyKind([datetime]'2026-10-14T12:00:00', 'Utc')
    Get-ChildItem -LiteralPath $work -Recurse | ForEach-Object { $_.LastWriteTimeUtc = $when }

    $script = Join-Path $PSScriptRoot 'New-Dashboard.ps1'
    # New-Dashboard.ps1 writes the JSON straight to the console, so run it in a child process of the same
    # PowerShell (pwsh or Windows PowerShell 5.1) and read that output.
    $exe = (Get-Process -Id $PID).Path
    $json = & $exe -NoProfile -ExecutionPolicy Bypass -File $script -WorkRoot $work -AsJson -ConfigPath (Join-Path $root 'none.json')
    if ($LASTEXITCODE -ne 0) { throw "New-Dashboard.ps1 -AsJson failed (exit $LASTEXITCODE)." }
    $model = ($json -join "`n") | ConvertFrom-Json
    $expected = (Get-Content -LiteralPath $expectedFile -Raw | ConvertFrom-Json).items

    $fields = 'kind', 'id', 'title', 'type', 'adoState', 'lane', 'laneGuessed', 'bucket', 'stage'
    $bad = 0
    foreach ($e in $expected) {
        $it = @($model.items | Where-Object { $_.folder -eq $e.folder })[0]
        if (-not $it) { Write-Host "::error::$($e.folder): not in New-Dashboard.ps1's items"; $bad++; continue }
        foreach ($k in $fields) {
            if (-not ($e.PSObject.Properties.Name -contains $k)) { continue }
            $want = $e.$k | ConvertTo-Json -Compress -Depth 5
            $have = $it.$k | ConvertTo-Json -Compress -Depth 5
            if ($want -ne $have) { Write-Host "::error::$($e.folder).$k is $have, Workshop's contract says $want"; $bad++ }
        }
    }
    if ($bad) { Write-Host "$bad difference(s) from Workshop's .work contract (docs/work-format.md)."; exit 1 }
    Write-Host "Work format: New-Dashboard.ps1 reads Workshop's example workspace the way docs/work-format.md says ($(@($expected).Count) items)."
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
