<#
.SYNOPSIS
    Creates a practice workspace with made-up repos for a dry run of the eng-agents pipeline.

.DESCRIPTION
    Creates <Path> containing:
      AGENTS.md      practice repo map (already filled in)
      .work\         empty pipeline folder
      shared-lib\    .NET shared library (referenced by relative path)
      orders-api\    .NET API, Clean Architecture, xUnit, with a planted bug (work item 101)
      orders-ui\     Angular app with Karma unit tests and Playwright tests using page.route mocks

    Each repo is a git repo on branch main, with an "origin" remote pointing to a local
    bare repo in <Path>-remotes, so fetch and branch commands behave like a real remote.
    Pushing to it is harmless, but the agents are denied push anyway.

.EXAMPLE
    pwsh ./practice/New-PracticeWorkspace.ps1

.EXAMPLE
    pwsh ./practice/New-PracticeWorkspace.ps1 -Path ~/eng-practice
#>
[CmdletBinding()]
param(
    [string]$Path = (Join-Path $(if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }) "eng-practice")
)

$ErrorActionPreference = "Stop"

function Invoke-Git {
    # Simple function (no param block) so flags like -q pass straight through in $args.
    $repo = $args[0]
    $gitArgs = @($args | Select-Object -Skip 1)
    $out = & git -C $repo @gitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($gitArgs -join ' ') failed in ${repo}: $out" }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git is not installed." }

$Path = [System.IO.Path]::GetFullPath($Path)
$remotes = "$Path-remotes"
if (Test-Path $Path) { throw "$Path already exists. Delete it (and $remotes) or pass -Path <new folder>." }

$source = $PSScriptRoot
New-Item -ItemType Directory -Path $Path | Out-Null
New-Item -ItemType Directory -Path (Join-Path $Path ".work") | Out-Null
New-Item -ItemType Directory -Path $remotes -Force | Out-Null
Copy-Item (Join-Path $source "workspace/AGENTS.md") (Join-Path $Path "AGENTS.md")

foreach ($repoDir in Get-ChildItem (Join-Path $source "repos") -Directory) {
    $name = $repoDir.Name
    $repo = Join-Path $Path $name
    Copy-Item $repoDir.FullName $repo -Recurse

    Invoke-Git $repo init -q -b main
    # Local identity only if none is configured, so commits work on a fresh machine.
    $null = & git -C $repo config user.email 2>&1
    if ($LASTEXITCODE -ne 0) {
        Invoke-Git $repo config user.email "practice@example.com"
        Invoke-Git $repo config user.name "Practice"
    }
    Invoke-Git $repo add -A
    Invoke-Git $repo commit -q -m "Initial practice code"

    $bare = Join-Path $remotes "$name.git"
    $out = & git init -q --bare -b main $bare 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git init --bare failed: $out" }
    Invoke-Git $repo remote add origin $bare
    Invoke-Git $repo push -q -u origin main

    Write-Host "  created $name"
}

Write-Host ""
Write-Host "Practice workspace ready: $Path"
Write-Host "Local remotes:            $remotes"
Write-Host ""
Write-Host "Next:"
Write-Host "  cd $Path"
Write-Host "  opencode"
Write-Host ""
Write-Host "Work items to paste are in: $(Join-Path $source 'work-items')"
Write-Host "To start over: delete both folders above and run this script again."
