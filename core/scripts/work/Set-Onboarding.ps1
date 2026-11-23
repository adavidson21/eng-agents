<#
.SYNOPSIS
    Records a step of a product's onboarding (/onboard-product, Core 4.10.0) in .work/_onboarding/<product>.md.

.DESCRIPTION
    One small file per product. Workshop's Builds reads it to light up the steps of the product's new line:
    Add (Workshop), Scan, Fill the gaps (open gaps for the product in .work/gaps.md), Trial run, Live.
    Lines, each replaced (never repeated) when the step runs again:

      - Product: <name>
      - Scan: done <yyyy-mm-dd> | <repos scanned>
      - Trial: <local id of the trial item>
      - Live: <yyyy-mm-dd>

    Only /onboard-product writes this file, through this script. Prints the file path.

.EXAMPLE
    .\Set-Onboarding.ps1 -WorkRoot .work -Product "Sample Portal" -Step scan -Value "portal-api, portal-ui"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$Product,
    [Parameter(Mandatory = $true)] [ValidateSet("scan", "trial", "live")] [string]$Step,
    [string]$Value = "",
    [string]$WorkRoot = ".work"
)

$ErrorActionPreference = "Stop"

$name = ($Product -replace "[\r\n|]+", " ").Trim()
if (-not $name) { throw "Give the product's name." }
$slug = (($name.ToLowerInvariant() -replace "[^a-z0-9]+", "-").Trim("-"))
if (-not $slug) { $slug = "product" }
if ($slug.Length -gt 60) { $slug = $slug.Substring(0, 60).TrimEnd("-") }

$dir = Join-Path $WorkRoot "_onboarding"
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$file = Join-Path $dir "$slug.md"

$lines = New-Object System.Collections.ArrayList
if (Test-Path -LiteralPath $file) { foreach ($l in [System.IO.File]::ReadAllLines($file)) { [void]$lines.Add($l) } }
else { [void]$lines.Add("# Onboarding: $name"); [void]$lines.Add(""); [void]$lines.Add("- Product: $name") }

$today = (Get-Date).ToString("yyyy-MM-dd")
$v = ($Value -replace "[\r\n|]+", " ").Trim()
$label = @{ scan = "Scan"; trial = "Trial"; live = "Live" }[$Step]
$text = switch ($Step) {
    "scan" { "- Scan: done $today$(if ($v) { " | $v" })" }
    "trial" { if (-not $v) { throw "Give the trial item's local id (-Value L12)." }; "- Trial: $v" }
    "live" { "- Live: $today" }
}

$at = -1
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match "^- ${label}:") { $at = $i; break } }
if ($at -ge 0) { $lines[$at] = $text } else { [void]$lines.Add($text) }

$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($file, (($lines -join "`n").TrimEnd() + "`n"), $enc)
Write-Output (Resolve-Path -LiteralPath $file).Path
