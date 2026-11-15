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
    }
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

# Lift per case that ran in both arms: Tandem's pass rate minus the baseline's, in points.
function Get-Lift {
    param($Results)
    $out = @()
    $byCase = @{}
    foreach ($r in $Results) {
        if ($r.skipped -or $null -eq $r.rate) { continue }
        $a = if ($r.arm) { "$($r.arm)" } else { "tandem" }
        if (-not $byCase.ContainsKey($r.case)) { $byCase[$r.case] = @{} }
        $byCase[$r.case][$a] = [int]$r.rate
    }
    foreach ($k in ($byCase.Keys | Sort-Object)) {
        $v = $byCase[$k]
        if ($v.ContainsKey("tandem") -and $v.ContainsKey("baseline")) {
            $out += [pscustomobject]@{ case = $k; tandem = $v["tandem"]; baseline = $v["baseline"]; lift = ($v["tandem"] - $v["baseline"]) }
        }
    }
    return $out
}
