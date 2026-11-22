<#
.SYNOPSIS
    What each Tandem command loads and reads, in estimated tokens, biggest first: up front (its command file, its
    agent and the always-loaded AGENTS.md) and while it runs (the guides, templates and stacks it names). No model.

.DESCRIPTION
    -Write saves the same list to evals/commands.json (with each command's files and a hash of them), which
    Workshop's Bench reads for its Overview and to mark results stale after a prompt change. -Check fails when
    evals/commands.json is out of date (CI). After changing a command, agent, guide, template or stack, run
    -Write and commit the file.

    -Check also fails when a command loads more than -MaxTokens up front, or the always-loaded AGENTS.md is more
    than -MaxBaseTokens. Tandem has to fit a local model's context window too (Workshop's docs/local-models.md),
    and opencode's own prompt and the repo map come on top, so prompts may only shrink below these lines.

.EXAMPLE
    ./evals/Get-PromptSize.ps1
.EXAMPLE
    ./evals/Get-PromptSize.ps1 -Write
#>
[CmdletBinding()]
param([switch]$AsJson, [switch]$Write, [switch]$Check, [int]$MaxTokens = 8000, [int]$MaxBaseTokens = 3000)
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
    $over = @($infos | Where-Object { $_.tokens -gt $MaxTokens })
    $base = if ($infos.Count) { [math]::Ceiling($infos[0].baseChars / 4) } else { 0 }
    if ($over.Count -or $base -gt $MaxBaseTokens) {
        foreach ($s in $over) { Write-Output "/$($s.command) loads $($s.tokens) tokens up front, over the budget of $MaxTokens. Trim it (./evals/Suggest-Trim.ps1 -Command $($s.command))." }
        if ($base -gt $MaxBaseTokens) { Write-Output "core/AGENTS.md is $base tokens, over the budget of $MaxBaseTokens. It loads with every command." }
        exit 1
    }
    Write-Output "evals/commands.json is up to date ($($infos.Count) commands, each within $MaxTokens tokens up front; AGENTS.md $base of $MaxBaseTokens)."; exit 0
}
if ($AsJson) { $json; exit 0 }
Write-Output "| Command | Agent | Up front | While running | Command | Agent | AGENTS.md |"
Write-Output "|---|---|---|---|---|---|---|"
foreach ($s in ($infos | Sort-Object -Property tokens -Descending)) {
    Write-Output ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} |" -f $s.command, $(if ($s.agent) { $s.agent } else { "(default)" }), $s.tokens, $s.readTokens, [math]::Ceiling($s.commandChars / 4), [math]::Ceiling($s.agentChars / 4), [math]::Ceiling($s.baseChars / 4))
}
Write-Output ""
Write-Output "Tokens estimated at 4 characters each. While running: the guides, templates and stacks a command names."
