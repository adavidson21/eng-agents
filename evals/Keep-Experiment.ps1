<#
.SYNOPSIS
    Keep or drop an experiment. Keep copies its changed file into core/ (your working tree; you review and commit
    it) and refreshes evals/commands.json. Drop marks it dropped. Neither runs git.

.EXAMPLE
    ./evals/Keep-Experiment.ps1 -Id trim-tsd-20261115-101500-ab12
.EXAMPLE
    ./evals/Keep-Experiment.ps1 -Id fix-spec-20261115-101500-ab12 -Drop
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Id, [switch]$Drop)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib/EvalLib.ps1")
. (Join-Path $PSScriptRoot "lib/Experiments.ps1")
$m = Read-Experiment $Id
if ($Drop) { Set-ExperimentStatus $Id "dropped"; Write-Output "Dropped $Id."; exit 0 }
$src = Join-Path (Join-Path (Join-Path (Get-ExperimentsRoot) $Id) "overlay") $m.file
$dest = Join-Path $script:RepoRoot "core/$($m.file)"
Copy-Item -LiteralPath $src -Destination $dest -Force
Set-ExperimentStatus $Id "kept"
$null = & (Join-Path $PSScriptRoot "Get-PromptSize.ps1") -Write
Write-Output "Kept ${Id}: core/$($m.file) changed in your working tree, and evals/commands.json refreshed."
Write-Output "Review and commit: git diff core/$($m.file)"
Write-Output "Then ./install.ps1 so your Tandem uses it."
exit 0
