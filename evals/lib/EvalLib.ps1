<#
.SYNOPSIS
    Shared helpers for Invoke-Evals.ps1 and Test-Graders.ps1. Dot-source it.
#>

$script:EvalsRoot = Split-Path $PSScriptRoot -Parent
$script:RepoRoot = Split-Path $script:EvalsRoot -Parent
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)

function Invoke-EvalGit {
    param([string]$Repo, [string[]]$GitArgs)
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    $out = & git -C $Repo @GitArgs 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($code -ne 0) { throw "git $($GitArgs -join ' ') failed in ${Repo}: $out" }
    return $out.Trim()
}

function Read-Case {
    param([string]$Path)
    $c = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    $c | Add-Member -NotePropertyName CaseFile -NotePropertyValue $Path -Force
    return $c
}

function Get-CaseList {
    param($Value)
    if ($null -eq $Value) { return @() }
    return @($Value)
}

# Copy every file of $From into $To. A file named progress-add.md is appended to progress.md instead.
function Copy-Overlay {
    param([string]$From, [string]$To)
    if (-not (Test-Path -LiteralPath $From)) { throw "Missing fixture folder $From" }
    New-Item -ItemType Directory -Path $To -Force | Out-Null
    foreach ($f in (Get-ChildItem -LiteralPath $From -Recurse -File)) {
        $rel = $f.FullName.Substring((Resolve-Path -LiteralPath $From).Path.Length).TrimStart("\", "/")
        $dest = Join-Path $To $rel
        New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
        if ($f.Name -eq "progress-add.md") {
            $target = Join-Path (Split-Path $dest -Parent) "progress.md"
            $existing = if (Test-Path -LiteralPath $target) { [IO.File]::ReadAllText($target) } else { "" }
            [IO.File]::WriteAllText($target, $existing.TrimEnd() + "`n" + [IO.File]::ReadAllText($f.FullName), $script:Utf8)
        }
        else {
            Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
        }
    }
}

<#
  Builds a fresh workspace for a case in $Root and returns where things are:
    Root   the workspace root (opencode starts here)
    Repo   the sample-api git repo
    Work   the case's work item folder (.work/<workItem>), or $null
    Base   the sample-api commit the agent starts from (HEAD after setup)
#>
function New-EvalWorkspace {
    param($Case, [string]$Root)
    Copy-Item -Path (Join-Path $script:EvalsRoot "workspace/*") -Destination $Root -Recurse -Force
    # Extra input files for a case (a doc with planted mistakes, a request note), before the first commit.
    foreach ($x in (Get-CaseList $Case.files)) { Copy-Overlay (Join-Path $script:EvalsRoot "fixtures/extra/$($x.from)") (Join-Path $Root $x.to) }
    $repo = Join-Path $Root "sample-api"
    Invoke-EvalGit $repo @("init", "-q", "-b", "main") | Out-Null
    Invoke-EvalGit $repo @("config", "user.email", "evals@example.invalid") | Out-Null
    Invoke-EvalGit $repo @("config", "user.name", "Tandem evals") | Out-Null
    Invoke-EvalGit $repo @("config", "commit.gpgsign", "false") | Out-Null
    Invoke-EvalGit $repo @("add", "-A") | Out-Null
    Invoke-EvalGit $repo @("commit", "-q", "-m", "Initial") | Out-Null

    if ($Case.branch) { Invoke-EvalGit $repo @("checkout", "-q", "-b", $Case.branch) | Out-Null }
    foreach ($rc in (Get-CaseList $Case.repoCommits)) {
        Copy-Overlay (Join-Path $script:EvalsRoot "fixtures/repo/$($rc.from)") $repo
        Invoke-EvalGit $repo @("add", "-A") | Out-Null
        Invoke-EvalGit $repo @("commit", "-q", "-m", $rc.message) | Out-Null
    }
    foreach ($w in (Get-CaseList $Case.work)) {
        Copy-Overlay (Join-Path $script:EvalsRoot "fixtures/work/$($w.from)") (Join-Path $Root ".work/$($w.to)")
    }
    $work = if ($Case.workItem) { Join-Path $Root ".work/$($Case.workItem)" } else { $null }
    return [pscustomobject]@{
        Root = $Root
        Repo = $repo
        Work = $work
        Base = (Invoke-EvalGit $repo @("rev-parse", "HEAD"))
        Case = $Case
        WorkSnapshot = (Get-TreeSnapshot (Join-Path $Root ".work"))
    }
}

# Every file under a folder with a hash of its contents, one line each, sorted ("" when the folder is missing).
function Get-TreeSnapshot([string]$Dir) {
    if (-not (Test-Path -LiteralPath $Dir)) { return "" }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $root = (Resolve-Path -LiteralPath $Dir).Path
    $lines = foreach ($f in (Get-ChildItem -LiteralPath $root -Recurse -File | Sort-Object FullName)) {
        $h = ($sha.ComputeHash([IO.File]::ReadAllBytes($f.FullName)) | ForEach-Object { $_.ToString("x2") }) -join ""
        "$($f.FullName.Substring($root.Length).Replace('\', '/')) $h"
    }
    return ($lines -join "`n")
}

# Applies a golden output (what a good or bad agent run would leave behind) to a workspace.
function Set-GoldenOutput {
    param($Ws, [string]$GoldenDir)
    $w = Join-Path $GoldenDir "work"
    if (Test-Path -LiteralPath $w) { Copy-Overlay $w (Join-Path $Ws.Root ".work") }
    $r = Join-Path $GoldenDir "repo"
    if (Test-Path -LiteralPath $r) {
        Copy-Overlay $r $Ws.Repo
        Invoke-EvalGit $Ws.Repo @("add", "-A") | Out-Null
        Invoke-EvalGit $Ws.Repo @("commit", "-q", "-m", "Golden output") | Out-Null
    }
    $u = Join-Path $GoldenDir "uncommitted"
    if (Test-Path -LiteralPath $u) { Copy-Overlay $u $Ws.Repo }
}

function New-TempDir {
    param([string]$Prefix)
    $d = Join-Path ([IO.Path]::GetTempPath()) ("$Prefix-" + [guid]::NewGuid().ToString("N").Substring(0, 12))
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    return $d
}

<#
  The baseline arm's opencode config: your own settings with Tandem's parts taken out, so a plain prompt runs
  on the same model, providers and permissions but without Tandem's rules, memory, agents or commands.
  Returns Name (file name), Text (contents) and Note (what was done, for the run log).
#>
function New-PlainOpencodeConfig {
    param([string]$UserDir)
    $json = Join-Path $UserDir "opencode.json"
    $jsonc = Join-Path $UserDir "opencode.jsonc"
    if (Test-Path -LiteralPath $json) {
        $o = Get-Content -Raw -LiteralPath $json | ConvertFrom-Json
        $dropped = @()
        foreach ($k in @("instructions", "agent", "command", "mode")) {
            if ($o.PSObject.Properties[$k]) { $o.PSObject.Properties.Remove($k); $dropped += $k }
        }
        $note = if ($dropped.Count) { "your opencode.json without $($dropped -join ', ')" } else { "your opencode.json" }
        return [pscustomobject]@{ Name = "opencode.json"; Text = ($o | ConvertTo-Json -Depth 32); Note = $note }
    }
    if (Test-Path -LiteralPath $jsonc) {
        # install.ps1 never edits a .jsonc, so it holds none of Tandem's parts.
        return [pscustomobject]@{ Name = "opencode.jsonc"; Text = [IO.File]::ReadAllText($jsonc); Note = "your opencode.jsonc as is" }
    }
    return [pscustomobject]@{ Name = "opencode.json"; Text = '{ "$schema": "https://opencode.ai/config.json" }'; Note = "an empty config (you have no opencode.json)" }
}

# Approves a gate file the way /approve does on disk: its "Status: DRAFT" line becomes "Status: APPROVED".
# True when the file now says APPROVED, false when it is missing or has no Status line.
function Approve-GateFile {
    param([string]$Work, [string]$Name)
    if (-not $Work) { return $false }
    $p = Join-Path $Work $Name
    if (-not (Test-Path -LiteralPath $p)) { return $false }
    $t = [IO.File]::ReadAllText($p)
    if ($t -match '(?m)^\s*Status:\s*APPROVED\s*$') { return $true }
    if ($t -notmatch '(?m)^\s*Status:\s*DRAFT\s*$') { return $false }
    $t = [regex]::Replace($t, '(?m)^(\s*)Status:\s*DRAFT\s*$', '${1}Status: APPROVED')
    [IO.File]::WriteAllText($p, $t, $script:Utf8)
    return $true
}

# Lift per case (and model) that ran in both arms: Tandem's pass rate minus the baseline's, in points.
function Get-Lift {
    param($Results)
    $out = @()
    $byCase = @{}
    foreach ($r in $Results) {
        if ($r.skipped -or $null -eq $r.rate) { continue }
        $a = if ($r.arm) { "$($r.arm)" } else { "tandem" }
        $k = "$($r.case)|$($r.model)"
        if (-not $byCase.ContainsKey($k)) { $byCase[$k] = @{ case = "$($r.case)"; model = $r.model } }
        $byCase[$k][$a] = [int]$r.rate
    }
    foreach ($k in ($byCase.Keys | Sort-Object)) {
        $v = $byCase[$k]
        if ($v.ContainsKey("tandem") -and $v.ContainsKey("baseline")) {
            $out += [pscustomobject]@{ case = $v.case; model = $v.model; tandem = $v["tandem"]; baseline = $v["baseline"]; lift = ($v["tandem"] - $v["baseline"]) }
        }
    }
    return $out
}

# ------------------------------------------------------------------ usage (results version 3)

function New-Usage {
    return [ordered]@{ known = $false; input = 0; output = 0; reasoning = 0; cacheRead = 0; cacheWrite = 0; cost = 0.0; toolCalls = 0; questions = 0 }
}

function Add-Usage($A, $B) {
    $o = New-Usage
    foreach ($k in @("input", "output", "reasoning", "cacheRead", "cacheWrite", "toolCalls", "questions")) { $o[$k] = [int64]$A[$k] + [int64]$B[$k] }
    $o.cost = [double]$A.cost + [double]$B.cost
    $o.known = [bool]($A.known -or $B.known)
    return $o
}

function Get-UsageTokens($U) { return [int64]($U.input + $U.output + $U.reasoning) }

<#
  Reads `opencode run --format json` output (one JSON event per line) and adds up what the run used:
  step_finish events carry tokens (input, output, reasoning, cache read and write) and cost; tool_use events are
  tool calls, and a tool named "question" is the agent asking. known is false when no step_finish was seen
  (an older opencode, or a run that never got going), so a missing number is not shown as 0.
#>
function Get-RunUsage {
    param([string]$Stdout)
    $u = New-Usage
    if (-not $Stdout) { return $u }
    foreach ($line in ($Stdout -split "\r?\n")) {
        $t = $line.Trim()
        if (-not $t.StartsWith("{")) { continue }
        try { $e = $t | ConvertFrom-Json } catch { continue }
        if ($e.type -eq "step_finish" -and $e.part) {
            $tk = $e.part.tokens
            if ($tk) {
                $u.known = $true
                $u.input += [int64]$tk.input; $u.output += [int64]$tk.output; $u.reasoning += [int64]$tk.reasoning
                if ($tk.cache) { $u.cacheRead += [int64]$tk.cache.read; $u.cacheWrite += [int64]$tk.cache.write }
            }
            if ($null -ne $e.part.cost) { $u.cost += [double]$e.part.cost }
        }
        elseif ($e.type -eq "tool_use" -and $e.part) {
            $u.toolCalls++
            if ("$($e.part.tool)" -eq "question") { $u.questions++ }
        }
    }
    return $u
}

# Failed verifies in the run's .work progress logs (do-task's "Verify: ... -> FAIL" or a verify=FAIL Stats value).
function Get-VerifyFails($Ws) {
    $work = Join-Path $Ws.Root ".work"
    if (-not (Test-Path -LiteralPath $work)) { return 0 }
    $n = 0
    foreach ($f in (Get-ChildItem -LiteralPath $work -Recurse -File -Filter progress.md -ErrorAction SilentlyContinue)) {
        $t = [IO.File]::ReadAllText($f.FullName)
        $n += [regex]::Matches($t, '(?mi)(^\s*-\s*Verify:.*->\s*FAIL\b|\bverify=FAIL\b)').Count
    }
    return $n
}

# Per case and arm: mean tokens, cost, questions and rework per run, and tokens and cost per passing run.
function Get-CaseUsageSummary($Runs, [int]$Passes) {
    $runs = @($Runs)
    $sum = { param($list, $key) $t = 0.0; foreach ($r in $list) { $t += [double]$r[$key] }; $t }
    $known = @($runs | Where-Object { $_["usageKnown"] })
    $o = [ordered]@{ usageKnown = ($known.Count -gt 0); meanTokens = $null; meanCost = $null; tokensPerPass = $null; costPerPass = $null; meanQuestions = 0; meanToolCalls = 0; meanVerifyFails = 0 }
    if ($runs.Count) {
        $o.meanQuestions = [math]::Round((& $sum $runs "questions") / $runs.Count, 1)
        $o.meanToolCalls = [math]::Round((& $sum $runs "toolCalls") / $runs.Count, 1)
        $o.meanVerifyFails = [math]::Round((& $sum $runs "verifyFails") / $runs.Count, 1)
    }
    if ($known.Count) {
        $tok = & $sum $known "tokens"
        $cost = & $sum $known "cost"
        $o.meanTokens = [int64][math]::Round($tok / $known.Count)
        $o.meanCost = [math]::Round($cost / $known.Count, 4)
        if ($Passes -gt 0) { $o.tokensPerPass = [int64][math]::Round($tok / $Passes); $o.costPerPass = [math]::Round($cost / $Passes, 4) }
    }
    return $o
}

# ------------------------------------------------------------------ prompt size (no model)

<#
  What each command loads and reads. Up front: its command file, its agent file and the always-loaded core
  AGENTS.md (`tokens`, estimated at 4 characters each so commands compare fairly). While it runs: the guides,
  templates and stacks its command and agent files name as {{ENG_HOME}}/<folder>/<file> (`readTokens`).
  `files` lists everything above plus named scripts, relative to the repo; `hash` (12 hex) changes when any of
  them does, so a result can tell it is stale after a prompt change (results version 4, -Affected).
#>
function Get-CommandInfos {
    param([string]$Core = (Join-Path $script:RepoRoot "core"))
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $read = { param($p) if (Test-Path -LiteralPath $p) { [IO.File]::ReadAllText($p) } else { "" } }
    $repo = Split-Path -Parent ([IO.Path]::GetFullPath($Core))
    $agentsMd = Join-Path $Core "AGENTS.md"
    $base = & $read $agentsMd
    $out = @()
    foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $Core "commands") -Filter *.md | Sort-Object Name)) {
        $text = [IO.File]::ReadAllText($f.FullName)
        $agent = ([regex]::Match($text, '(?m)^agent:\s*([\w-]+)\s*$')).Groups[1].Value
        $agentText = ""
        $files = New-Object System.Collections.Generic.List[string]
        $files.Add("core/commands/$($f.Name)")
        $files.Add("core/AGENTS.md")
        if ($agent) {
            $agentText = & $read (Join-Path $Core "agents/$agent.md")
            if ($agentText) { $files.Add("core/agents/$agent.md") }
        }
        $refs = New-Object System.Collections.Generic.HashSet[string]
        $queue = New-Object System.Collections.Generic.Queue[string]
        $queue.Enqueue($text); $queue.Enqueue($agentText)
        $readChars = 0
        while ($queue.Count) {
            $t = $queue.Dequeue()
            foreach ($m in [regex]::Matches($t, '\{\{ENG_HOME\}\}/((?:guides|templates|stacks|scripts)/[A-Za-z0-9_./-]+\.(?:md|ps1|json))')) {
                $rel = $m.Groups[1].Value
                if (-not $refs.Add($rel)) { continue }
                $full = Join-Path $Core $rel
                if (-not (Test-Path -LiteralPath $full)) { continue }
                $files.Add("core/$rel")
                $body = [IO.File]::ReadAllText($full)
                if ($rel -notlike "scripts/*") { $readChars += $body.Length; $queue.Enqueue($body) }
            }
        }
        $sorted = @($files | Select-Object -Unique | Sort-Object)
        $all = ($sorted | ForEach-Object { "$_`n" + (& $read (Join-Path $repo $_)) }) -join "`n"
        $hash = (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($all -replace "`r`n", "`n"))) | ForEach-Object { $_.ToString("x2") }) -join "").Substring(0, 12)
        $out += [pscustomobject]@{
            command = $f.BaseName; agent = $(if ($agent) { $agent } else { $null })
            commandChars = $text.Length; agentChars = $agentText.Length; baseChars = $base.Length
            tokens = [int][math]::Ceiling(($text.Length + $agentText.Length + $base.Length) / 4)
            readTokens = [int][math]::Ceiling($readChars / 4)
            files = $sorted; hash = $hash
        }
    }
    return $out
}

# Kept for callers from Core 3.2.0: the same rows without the read list.
function Get-PromptSizes {
    param([string]$Core = (Join-Path $script:RepoRoot "core"))
    return @(Get-CommandInfos -Core $Core)
}

# The commands a case runs in its tandem arm.
function Get-CaseCommands($Case) {
    if ($Case.steps) { return @($Case.steps | Where-Object { $_.command } | ForEach-Object { "$($_.command)" } | Select-Object -Unique) }
    if ($Case.command) { return @("$($Case.command)") }
    return @()
}

# One hash for everything a case's commands load and read (12 hex), or $null when it runs none.
function Get-CaseFilesHash($Case) {
    if (-not $script:CommandInfos) { $script:CommandInfos = @(Get-CommandInfos) }
    $hs = @(Get-CaseCommands $Case | ForEach-Object { $n = $_; @($script:CommandInfos | Where-Object { $_.command -eq $n })[0].hash } | Where-Object { $_ })
    if (-not $hs.Count) { return $null }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    return (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($hs -join ","))) | ForEach-Object { $_.ToString("x2") }) -join "").Substring(0, 12)
}

<#
  Which cases to run after a prompt change: those whose files hash differs from the newest results file that
  ran them in the tandem arm, plus those never run. Returns @{ Run = names; Why = @{ name = reason } }.
#>
function Get-AffectedCases {
    param([object[]]$CaseFiles, [string]$ResultsDir)
    $last = @{}
    foreach ($f in @(Get-ChildItem -LiteralPath $ResultsDir -Filter *.json -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)) {
        try { $j = Get-Content -Raw -LiteralPath $f.FullName | ConvertFrom-Json } catch { continue }
        foreach ($r in @($j.cases)) {
            if ($r.skipped -or ($r.arm -and $r.arm -ne "tandem")) { continue }
            $last["$($r.case)"] = [pscustomobject]@{ hash = $r.filesHash; file = $f.Name }
        }
    }
    $run = @(); $why = @{}
    foreach ($cf in $CaseFiles) {
        $c = Read-Case $cf.FullName
        $h = Get-CaseFilesHash $c
        $prev = $last[$cf.BaseName]
        if (-not $prev) { $run += $cf.BaseName; $why[$cf.BaseName] = "never run" }
        elseif (-not $prev.hash) { $run += $cf.BaseName; $why[$cf.BaseName] = "no files hash in $($prev.file)" }
        elseif ($prev.hash -ne $h) { $run += $cf.BaseName; $why[$cf.BaseName] = "prompts changed since $($prev.file)" }
    }
    return @{ Run = $run; Why = $why }
}

<#
  An experiment's Tandem: a scratch copy of this repo with the overlay's files laid over core/ (an overlay
  folder mirrors core/, for example <overlay>/commands/plan.md), installed into a scratch opencode config
  folder with your own opencode.json copied in first (model, providers). Returns the XDG_CONFIG_HOME to run
  the tandem arm with. Your real Tandem is not touched.
#>
function New-ExperimentConfig {
    param([string]$Overlay, [string]$UserDir)
    if (-not (Test-Path -LiteralPath $Overlay)) { throw "Overlay folder not found: $Overlay" }
    $scratch = New-TempDir "eval-experiment-repo"
    foreach ($item in @("core", "personal", "install.ps1", "update.ps1")) {
        $src = Join-Path $script:RepoRoot $item
        if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $scratch -Recurse -Force }
    }
    $root = (Resolve-Path -LiteralPath $Overlay).Path
    foreach ($f in (Get-ChildItem -LiteralPath $root -Recurse -File)) {
        $rel = $f.FullName.Substring($root.Length).TrimStart('\', '/')
        if ($rel -match '(^|[\\/])\.\.([\\/]|$)') { throw "Bad overlay path: $rel" }
        $dest = Join-Path (Join-Path $scratch "core") $rel
        New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
    }
    $xdg = New-TempDir "eval-experiment-config"
    $target = Join-Path $xdg "opencode"
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    foreach ($n in @("opencode.json", "opencode.jsonc")) {
        $u = Join-Path $UserDir $n
        if (Test-Path -LiteralPath $u) { Copy-Item -LiteralPath $u -Destination $target -Force }
    }
    $null = & (Join-Path $scratch "install.ps1") -Target $target 6>&1 2>&1
    return [pscustomobject]@{ XdgConfigHome = $xdg; Repo = $scratch }
}

# Prompt tokens for the commands a case runs in an arm (the baseline loads none of them).
function Get-CasePromptTokens($Case, [string]$Arm) {
    if ($Arm -eq "baseline") { return 0 }
    $cmds = @()
    if ($Case.steps) { $cmds = @($Case.steps | Where-Object { $_.command } | ForEach-Object { "$($_.command)" }) }
    elseif ($Case.command) { $cmds = @("$($Case.command)") }
    if (-not $script:CommandInfos) { $script:CommandInfos = @(Get-CommandInfos) }
    $sum = 0
    foreach ($c in ($cmds | Select-Object -Unique)) { $hit = @($script:CommandInfos | Where-Object { $_.command -eq $c })[0]; if ($hit) { $sum += $hit.tokens } }
    return $sum
}
