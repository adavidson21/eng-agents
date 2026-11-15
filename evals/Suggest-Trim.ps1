<#
.SYNOPSIS
    Trim experiments, no model: for one command (or agent), one experiment per "## " section, each with that
    section removed. Run them with Bench (or Invoke-Evals -Overlay) on the cases that use the command; a section
    whose removal drops nothing is a candidate to cut, since smaller prompts are cheaper.

.EXAMPLE
    ./evals/Suggest-Trim.ps1 -Command tsd
.EXAMPLE
    ./evals/Suggest-Trim.ps1 -Agent planner -Max 3
#>
[CmdletBinding()]
param([string]$Command, [string]$Agent, [int]$Max = 5)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib/EvalLib.ps1")
. (Join-Path $PSScriptRoot "lib/Experiments.ps1")
if (-not $Command -and -not $Agent) { throw "Pass -Command <name> or -Agent <name>." }
$file = if ($Command) { "commands/$Command.md" } else { "agents/$Agent.md" }
$name = if ($Command) { $Command } else { $Agent }
if ($name -notmatch '^[a-z0-9-]+$') { throw "Bad name: $name" }
$full = Join-Path $script:RepoRoot "core/$file"
if (-not (Test-Path -LiteralPath $full)) { throw "Not found: core/$file" }
$text = [IO.File]::ReadAllText($full)
$sections = @(Get-MdSections $text | Sort-Object { $_.End - $_.Start } -Descending | Select-Object -First $Max)
if (-not $sections.Count) { Write-Output "core/$file has no ## sections to trim."; exit 0 }
foreach ($s in $sections) {
    $new = $text.Remove($s.Start, $s.End - $s.Start)
    $tokens = [int][math]::Ceiling(($s.End - $s.Start) / 4)
    $e = Save-Experiment -Kind "trim" -Command $name -File $file -NewText $new -Reason "Remove the section `"$($s.Title)`" (about $tokens tokens) and check nothing drops."
    Write-Output "$($e.Id): without `"$($s.Title)`" (-$tokens tokens)"
}
Write-Output ""
Write-Output "Run one: ./evals/Invoke-Evals.ps1 -Overlay evals/experiments/<id>/overlay -Label <id> -Case <cases that use $name>"
exit 0
