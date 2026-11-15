<#
.SYNOPSIS
    Guard cases with no model: every agent's permissions, read from its frontmatter (with {{BASH:<tier>}} lines
    expanded the way install.ps1 does), give the answers in evals/guards/expected.json. opencode applies the last
    matching rule; * matches anything. Fails when an agent has no rows, so a new agent cannot ship unguarded.

    Run: pwsh -NoProfile -File evals/Test-AgentGuards.ps1  (add -AsJson for Bench)
#>
[CmdletBinding()]
param([switch]$AsJson)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib/EvalLib.ps1")

$core = Join-Path $script:RepoRoot "core"
$tiers = @{}
foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $core "permissions") -Filter *.json)) {
    $o = Get-Content -Raw -LiteralPath $f.FullName | ConvertFrom-Json
    $tiers[$f.BaseName] = @($o.PSObject.Properties | ForEach-Object { [pscustomobject]@{ Pattern = $_.Name; Action = "$($_.Value)" } })
}

# An agent's rules per kind (edit, bash, webfetch), in file order, tiers spliced in where they are included.
# A rule the file writes itself wins over the tier's rule for the same pattern (install.ps1 leaves the tier's out).
function Get-AgentRules([string]$Path) {
    $text = [IO.File]::ReadAllText($Path)
    $fm = [regex]::Match($text, '(?s)^---\r?\n(.*?)\r?\n---').Groups[1].Value
    $rules = @{}
    $kind = $null; $inPerm = $false
    $own = @{}
    foreach ($line in ($fm -split "\r?\n")) {
        $k = [regex]::Match($line, '^\s{4}"((?:[^"\\]|\\.)*)"\s*:')
        if ($k.Success) { $own[$k.Groups[1].Value] = $true }
    }
    foreach ($line in ($fm -split "\r?\n")) {
        if ($line -match '^permission:\s*$') { $inPerm = $true; continue }
        if (-not $inPerm) { continue }
        if ($line -match '^\S') { break }
        $one = [regex]::Match($line, '^\s{2}([a-z]+):\s*(allow|ask|deny)\s*$')
        if ($one.Success) { $rules[$one.Groups[1].Value] = @([pscustomobject]@{ Pattern = "*"; Action = $one.Groups[2].Value }); continue }
        $head = [regex]::Match($line, '^\s{2}([a-z]+):\s*$')
        if ($head.Success) { $kind = $head.Groups[1].Value; $rules[$kind] = @(); continue }
        $r = [regex]::Match($line, '^\s{4}"((?:[^"\\]|\\.)*)"\s*:\s*"?([a-z]+)"?\s*$')
        if (-not $r.Success -or -not $kind) { continue }
        $pat = $r.Groups[1].Value -replace '\\"', '"' -replace '\\\\', '\'
        $tierM = [regex]::Match($pat, '^\{\{BASH:([A-Za-z0-9_-]+)\}\}$')
        if ($tierM.Success) {
            foreach ($t in $tiers[$tierM.Groups[1].Value]) { if (-not $own.ContainsKey($t.Pattern)) { $rules[$kind] += $t } }
            continue
        }
        $rules[$kind] += [pscustomobject]@{ Pattern = $pat; Action = $r.Groups[2].Value }
    }
    return $rules
}

function Test-Glob([string]$Pattern, [string]$Text) {
    $p = $Pattern -replace '\{\{ENG_CONFIG\}\}', '__ENGCONFIG__'
    $rx = '^' + (([regex]::Escape($p)) -replace '\\\*\\\*', '.*' -replace '\\\*', '.*' -replace '\\\?', '.') + '$'
    return [regex]::IsMatch($Text, $rx)
}

function Get-Decision($Rules, [string]$Kind, [string]$Target) {
    $list = @($Rules[$Kind])
    if (-not $list.Count) { return "ask" }   # opencode's default for an unlisted kind
    $hit = $null
    foreach ($r in $list) { if (Test-Glob $r.Pattern $Target) { $hit = $r.Action } }
    if ($hit) { return $hit } else { return "ask" }
}

$expected = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "guards/expected.json") | ConvertFrom-Json
$agents = @(Get-ChildItem -LiteralPath (Join-Path $core "agents") -Filter *.md | Sort-Object Name)
$rows = @(); $failed = 0
foreach ($a in $agents) {
    $name = $a.BaseName
    $rules = Get-AgentRules $a.FullName
    $own = @($expected.agents.$name)
    if (-not $own.Count) { $rows += [ordered]@{ agent = $name; kind = "-"; target = "-"; expect = "rows"; got = "none"; pass = $false }; $failed++; continue }
    foreach ($e in (@($expected.all) + $own)) {
        $got = Get-Decision $rules $e.kind $e.target
        $ok = if ($e.expect -eq "not-allow") { $got -ne "allow" } else { $got -eq $e.expect }
        if (-not $ok) { $failed++ }
        $rows += [ordered]@{ agent = $name; kind = "$($e.kind)"; target = "$($e.target)"; expect = "$($e.expect)"; got = $got; pass = $ok }
    }
}
foreach ($n in @($expected.agents.PSObject.Properties.Name)) {
    if (-not (@($agents | Where-Object { $_.BaseName -eq $n }).Count)) { $rows += [ordered]@{ agent = $n; kind = "-"; target = "-"; expect = "agent"; got = "missing"; pass = $false }; $failed++ }
}

if ($AsJson) { [ordered]@{ version = 1; agents = $agents.Count; failed = $failed; rows = @($rows) } | ConvertTo-Json -Depth 4; if ($failed) { exit 1 } else { exit 0 } }
foreach ($r in $rows) {
    $line = "{0} {1,-20} {2,-5} {3} -> {4} (expect {5})" -f $(if ($r.pass) { "ok  " } else { "FAIL" }), $r.agent, $r.kind, $r.target, $r.got, $r.expect
    Write-Output $line
}
if ($failed) { Write-Output "$failed guard check(s) failed."; exit 1 }
Write-Output "Agent guards: all $($agents.Count) agents checked, all rows pass."
exit 0
