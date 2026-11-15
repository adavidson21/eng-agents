<#
.SYNOPSIS
    What each Tandem command loads and reads, in estimated tokens, biggest first: up front (its command file, its
    agent and the always-loaded AGENTS.md) and while it runs (the guides, templates and stacks it names). No model.

.DESCRIPTION
    -Write saves the same list to evals/commands.json (with each command's files and a hash of them), which
    Workshop's Bench reads for its Overview and to mark results stale after a prompt change. -Check fails when
    evals/commands.json is out of date (CI). After changing a command, agent, guide, template or stack, run
    -Write and commit the file.

.EXAMPLE
    ./evals/Get-PromptSize.ps1
.EXAMPLE
    ./evals/Get-PromptSize.ps1 -Write
#>
[CmdletBinding()]
param([switch]$AsJson, [switch]$Write, [switch]$Check)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib/EvalLib.ps1")
$infos = @(Get-CommandInfos)
$file = Join-Path $PSScriptRoot "commands.json"
$doc = [ordered]@{ version = 1; commands = @($infos | ForEach-Object {
    [ordered]@{ command = $_.command; agent = $_.agent; tokens = $_.tokens; readTokens = $_.readTokens; hash = $_.hash; files = @($_.files) } }) }
$json = (($doc | ConvertTo-Json -Depth 6) -replace "`r`n", "`n") + "`n"
if ($Write) { [IO.File]::WriteAllText($file, $json, $script:Utf8); Write-Output "Wrote $file ($($infos.Count) commands)."; exit 0 }
if ($Check) {
    $have = if (Test-Path -LiteralPath $file) { ([IO.File]::ReadAllText($file) -replace "`r`n", "`n") } else { "" }
    if ($have -ne $json) { Write-Output "evals/commands.json is out of date. Run ./evals/Get-PromptSize.ps1 -Write and commit it."; exit 1 }
    Write-Output "evals/commands.json is up to date ($($infos.Count) commands)."; exit 0
}
if ($AsJson) { $json; exit 0 }
Write-Output "| Command | Agent | Up front | While running | Command | Agent | AGENTS.md |"
Write-Output "|---|---|---|---|---|---|---|"
foreach ($s in ($infos | Sort-Object -Property tokens -Descending)) {
    Write-Output ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} |" -f $s.command, $(if ($s.agent) { $s.agent } else { "(default)" }), $s.tokens, $s.readTokens, [math]::Ceiling($s.commandChars / 4), [math]::Ceiling($s.agentChars / 4), [math]::Ceiling($s.baseChars / 4))
}
Write-Output ""
Write-Output "Tokens estimated at 4 characters each. While running: the guides, templates and stacks a command names."
