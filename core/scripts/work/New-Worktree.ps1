<#
.SYNOPSIS
    Makes a git worktree for one repo of a work item, so it can be built while the repo's own
    folder stays on another branch (another work item, or your uncommitted changes).

.DESCRIPTION
    Runs, from the workspace root:

        git -C <Repo> worktree add <Workspace>/.worktrees/<Folder>/<Repo> -b <Branch> <Base>

    With -Existing (the branch is already made, for /resume) it checks that branch out instead:

        git -C <Repo> worktree add <Workspace>/.worktrees/<Folder>/<Repo> <Branch>

    The worktree shares the repo's branches and commits, so pushing and diffs work from the
    repo's own folder too. Dot folders are never listed as repos, so .worktrees does not show
    up as one. Workshop's Loom removes an item's worktrees when you remove the item.

    The LAST line of output is the worktree path relative to the workspace (forward slashes),
    for the Path column of repos.md.

    Errors start with a word: NOREPO: (no such repo), EXISTS: (the worktree folder is already
    there), GIT: (git refused; its message follows).

.EXAMPLE
    .\New-Worktree.ps1 -Workspace . -Repo api -Folder 12345-export-retry -Branch dev/feature/12345-export-retry -Base origin/main
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$Repo,
    [Parameter(Mandatory = $true)] [string]$Folder,
    [Parameter(Mandatory = $true)] [string]$Branch,
    # Not needed with -Existing.
    [string]$Base,
    [switch]$Existing,
    [string]$Workspace = "."
)

$ErrorActionPreference = "Stop"

$ws = (Resolve-Path -LiteralPath $Workspace).Path
$repoRel = ($Repo -replace "\\", "/").Trim("/")
if (-not $repoRel -or $repoRel -match '(^|/)\.\.?(/|$)') { throw "NOREPO: '$Repo' is not a repo folder in the workspace." }
$repoPath = Join-Path $ws $repoRel
if (-not (Test-Path -LiteralPath (Join-Path $repoPath ".git"))) { throw "NOREPO: '$Repo' is not a git repo in the workspace." }
if ($Folder -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw "Folder must be the work folder name, like 12345-export-retry." }

if (-not $Existing -and -not $Base) { throw "Give -Base, or -Existing for a branch that is already made." }
$rel = ".worktrees/$Folder/$repoRel"
$target = Join-Path $ws $rel
if (Test-Path -LiteralPath $target) { throw "EXISTS: $rel is already there. Use it, or remove it with git -C $repoRel worktree remove $rel." }
New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null

$ErrorActionPreference = "Continue"
$gitArgs = if ($Existing) { @("-C", $repoPath, "worktree", "add", $target, $Branch) } else { @("-C", $repoPath, "worktree", "add", $target, "-b", $Branch, $Base) }
$out = & git @gitArgs 2>&1 | Out-String
$code = $LASTEXITCODE
$ErrorActionPreference = "Stop"
if ($code -ne 0) { throw ("GIT: " + $out.Trim()) }

Write-Output $rel
