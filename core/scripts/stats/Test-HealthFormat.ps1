<#
.SYNOPSIS
    Checks Get-PipelineStats.ps1 and Get-ReviewFindings.ps1 against Workshop's Tandem health contract.

.DESCRIPTION
    Workshop's Builds shows Tandem health (Health > Tandem) from its own port of these two scripts
    (connectors/opencode/lib/tandem-health.mjs). The two meet at Workshop's docs/tandem-health.md, with the
    synthetic example workspace docs/examples/work/ and what both must read from it, expected-health.json.
    This script copies that example into a temp folder (every file with the same modification time),
    runs both scripts with -AsJson, and compares the result with expected-health.json.

    CI checks out Workshop next to this repo. Locally: git clone https://github.com/adavidson21/workshop, then
    ./core/scripts/stats/Test-HealthFormat.ps1 -Workshop ../workshop

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
$expectedFile = Join-Path $example 'expected-health.json'
if (-not (Test-Path -LiteralPath $expectedFile)) { throw "No $expectedFile. Is $Workshop a Workshop checkout with Tandem health (Builds 4.4.0)?" }

# Same JSON text for the same data whatever the key order: sort object keys, keep array order.
function ConvertTo-Canonical($Value) {
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $parts = @($Value.PSObject.Properties | Sort-Object Name -CaseSensitive | ForEach-Object { (ConvertTo-Json $_.Name -Compress) + ':' + (ConvertTo-Canonical $_.Value) })
        return '{' + ($parts -join ',') + '}'
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        return '[' + (@($Value | ForEach-Object { ConvertTo-Canonical $_ }) -join ',') + ']'
    }
    if ($Value -is [double] -or $Value -is [decimal] -or $Value -is [single]) {
        if ([math]::Floor($Value) -eq $Value) { return ([long]$Value).ToString([System.Globalization.CultureInfo]::InvariantCulture) }
        return ([double]$Value).ToString('R', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return (ConvertTo-Json $Value -Compress)
}

# Patterns may tie on item count and findings; compare them in a fixed order.
function Get-SortedPatterns($Findings) {
    return @($Findings.patterns | Sort-Object { "$($_.repo)|$($_.category)" } -CaseSensitive)
}

$root = Join-Path ([IO.Path]::GetTempPath()) ("health-format-" + [guid]::NewGuid().ToString('N'))
$work = Join-Path $root '.work'
$bad = 0
try {
    New-Item -ItemType Directory -Path $root | Out-Null
    Copy-Item -LiteralPath $example -Destination $work -Recurse
    Get-ChildItem -LiteralPath $work -Filter 'expected*.json' | Remove-Item
    $when = [datetime]::SpecifyKind([datetime]'2026-10-18T12:00:00', 'Utc')
    Get-ChildItem -LiteralPath $work -Recurse | ForEach-Object { $_.LastWriteTimeUtc = $when }

    $exe = (Get-Process -Id $PID).Path
    $stats = & $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Get-PipelineStats.ps1') -WorkRoot $work -AsJson
    if ($LASTEXITCODE -ne 0) { throw "Get-PipelineStats.ps1 -AsJson failed (exit $LASTEXITCODE)." }
    $finds = & $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Get-ReviewFindings.ps1') -WorkRoot $work -AsJson
    if ($LASTEXITCODE -ne 0) { throw "Get-ReviewFindings.ps1 -AsJson failed (exit $LASTEXITCODE)." }
    $pipeline = ($stats -join "`n") | ConvertFrom-Json
    $pipeline.PSObject.Properties.Remove('generated')
    $findings = ($finds -join "`n") | ConvertFrom-Json
    $expected = Get-Content -LiteralPath $expectedFile -Raw | ConvertFrom-Json

    foreach ($k in @('version', 'since', 'summary', 'gates')) {
        $want = ConvertTo-Canonical $expected.pipeline.$k
        $have = ConvertTo-Canonical $pipeline.$k
        if ($want -ne $have) { Write-Host "::error::pipeline.$k is $have, Workshop's contract says $want"; $bad++ }
    }
    $wantItems = @($expected.pipeline.items); $haveItems = @($pipeline.items)
    if ($wantItems.Count -ne $haveItems.Count) { Write-Host "::error::pipeline.items: $($haveItems.Count) items, Workshop's contract says $($wantItems.Count)"; $bad++ }
    for ($i = 0; $i -lt [math]::Min($wantItems.Count, $haveItems.Count); $i++) {
        $want = ConvertTo-Canonical $wantItems[$i]; $have = ConvertTo-Canonical $haveItems[$i]
        if ($want -ne $have) { Write-Host "::error::pipeline.items[$i] ($($wantItems[$i].id)) is $have, Workshop's contract says $want"; $bad++ }
    }
    foreach ($k in @('version', 'since', 'itemsReviewed', 'findings')) {
        $want = ConvertTo-Canonical $expected.findings.$k
        $have = ConvertTo-Canonical $findings.$k
        if ($want -ne $have) { Write-Host "::error::findings.$k is $have, Workshop's contract says $want"; $bad++ }
    }
    $want = ConvertTo-Canonical (Get-SortedPatterns $expected.findings)
    $have = ConvertTo-Canonical (Get-SortedPatterns $findings)
    if ($want -ne $have) { Write-Host "::error::findings.patterns is $have, Workshop's contract says $want"; $bad++ }
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($bad) { Write-Host "Health format: $bad difference(s) from Workshop's docs/tandem-health.md."; exit 1 }
Write-Host "Health format: Get-PipelineStats.ps1 and Get-ReviewFindings.ps1 read Workshop's example workspace the way docs/tandem-health.md says."
