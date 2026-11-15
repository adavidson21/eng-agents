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
