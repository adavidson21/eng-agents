<#
.SYNOPSIS
    What each Tandem command loads before it does anything, in estimated tokens: its command file, its agent and the
    always-loaded AGENTS.md. No model. Biggest first, so the commands worth trimming are on top.

.EXAMPLE
    ./evals/Get-PromptSize.ps1
.EXAMPLE
    ./evals/Get-PromptSize.ps1 -AsJson
#>
[CmdletBinding()]
param([switch]$AsJson)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib/EvalLib.ps1")
$sizes = @(Get-PromptSizes | Sort-Object -Property tokens -Descending)
if ($AsJson) { $sizes | ConvertTo-Json -Depth 4; exit 0 }
Write-Output "| Command | Agent | Tokens (est.) | Command | Agent | AGENTS.md |"
Write-Output "|---|---|---|---|---|---|"
foreach ($s in $sizes) {
    Write-Output ("| {0} | {1} | {2} | {3} | {4} | {5} |" -f $s.command, $(if ($s.agent) { $s.agent } else { "(default)" }), $s.tokens, [math]::Ceiling($s.commandChars / 4), [math]::Ceiling($s.agentChars / 4), [math]::Ceiling($s.baseChars / 4))
}
Write-Output ""
Write-Output "Estimated at 4 characters per token. Files a command reads while it runs (templates, guides, stacks) are not counted."
