<#
.SYNOPSIS
    Fetches a GitHub pull request for a first-pass review and writes .work/pr-<number>/, like
    scripts/ado/Get-PullRequest.ps1 does for Azure DevOps.

.DESCRIPTION
    Read-only against GitHub: GET calls and one GraphQL query. It never posts comments, reviews or approvals.

    1. Reads the PR, its reviews, its comments and the issues it closes from GitHub.
    2. Finds the PR's repo among the folders in the workspace (by git remote, else by folder name).
    3. Fetches the PR (refs/pull/<number>/head, which works for forks too) and its base branch into private refs
       (refs/eng-agents/pr/<number>/source and .../target). It does not check anything out.
    4. Writes .work/pr-<number>/context.md and threads.md in the same format as the ADO script, so /pr-review
       works the same way.

    The LAST line of output is always the folder path. Lines starting with one of these words explain a failure:
      BADURL:    not a GitHub pull request link (.../<owner>/<repo>/pull/<number>)
      NOTFOUND:  GitHub has no such PR, or the token cannot see it
      NOTOKEN:   no GitHub token (see GitHubCommon.ps1)
      NOREPO:    the PR's repo is not cloned in the workspace
      FETCH:     git could not fetch the PR

.EXAMPLE
    .\Get-GitHubPullRequest.ps1 -Url "https://github.com/acme/web/pull/40"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Url,

    [string]$WorkRoot = ".work",

    # The folder that holds the repos. Default: the parent of WorkRoot.
    [string]$Workspace
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "GitHubCommon.ps1")

if ($Url -notmatch '^https?://[^/]+/([A-Za-z0-9][A-Za-z0-9-]{0,38})/([A-Za-z0-9._-]+)/pull/(\d+)') {
    throw "BADURL: that is not a GitHub pull request link: $Url. It looks like https://github.com/<owner>/<repo>/pull/<number>."
}
$owner = $Matches[1]; $name = $Matches[2]; $prId = [int]$Matches[3]
$repoFull = "$owner/$name"
$h = New-GitHubHeaders

function Invoke-Git {
    param([string[]]$GitArgs)
    $old = $env:GIT_TERMINAL_PROMPT
    $env:GIT_TERMINAL_PROMPT = "0"
    $ErrorActionPreference = "Continue"
    try {
        $out = & git @GitArgs 2>&1
        return [pscustomobject]@{ Code = $LASTEXITCODE; Out = (($out | ForEach-Object { "$_" }) -join "`n").Trim() }
    }
    finally { $env:GIT_TERMINAL_PROMPT = $old }
}

# ------------------------------------------------------------------ the PR
$pr = Invoke-GitHubRest $h "/repos/$repoFull/pulls/$prId" "pull request $repoFull#$prId"
$targetRef = [string]$pr.base.ref
$apiSource = [string]$pr.head.sha
$webLink = [string]$pr.html_url

# ------------------------------------------------------------------ the local repo
if (-not $Workspace) {
    $wr = if ([System.IO.Path]::IsPathRooted($WorkRoot)) { $WorkRoot } else { Join-Path (Get-Location).Path $WorkRoot }
    $Workspace = Split-Path -Parent ([System.IO.Path]::GetFullPath($wr))
}
$repoDirs = @(Get-ChildItem -LiteralPath $Workspace -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName ".git") })
$repoDir = $null
foreach ($d in $repoDirs) {
    $remote = (Invoke-Git @("-C", $d.FullName, "remote", "get-url", "origin")).Out
    if ((ConvertFrom-GitHubRemote $remote) -ieq $repoFull) { $repoDir = $d; break }
}
$repoNote = $null
if (-not $repoDir) {
    $repoDir = $repoDirs | Where-Object { $_.Name -ieq $name } | Select-Object -First 1
    if ($repoDir) { $repoNote = "Matched by folder name only: the folder's git remote does not point at $repoFull." }
}
if (-not $repoDir) { throw "NOREPO: $repoFull is not cloned in the workspace ($Workspace). Clone it there ($($pr.base.repo.clone_url)), then run this again." }
$folderName = $repoDir.Name
$repoPath = $repoDir.FullName

# ------------------------------------------------------------------ fetch, no checkout
$ns = "refs/eng-agents/pr/$prId"
$f = Invoke-Git @("-C", $repoPath, "fetch", "--no-tags", "--quiet", "origin", "+refs/pull/$($prId)/head:$ns/source", "+$($targetRef):$ns/target")
if ($f.Code -ne 0) { throw "FETCH: git could not fetch the PR in $folderName. $($f.Out)" }
$src = (Invoke-Git @("-C", $repoPath, "rev-parse", "$ns/source")).Out
$tgt = (Invoke-Git @("-C", $repoPath, "rev-parse", "$ns/target")).Out
$mbr = Invoke-Git @("-C", $repoPath, "merge-base", $tgt, $src)
if ($mbr.Code -ne 0) { throw "FETCH: no common history between the PR and $targetRef in $folderName (a shallow clone?). Run git -C $folderName fetch --unshallow, then try again." }
$mb = $mbr.Out
$moved = $null
if ($apiSource -and $src -ne $apiSource) { $moved = "The PR moved after GitHub answered; this review reads $($src.Substring(0,7)), the PR as fetched." }

$numstat = (Invoke-Git @("-C", $repoPath, "diff", "--numstat", $mb, $src)).Out
$fileRows = @()
$adds = 0; $dels = 0; $count = 0
foreach ($line in ($numstat -split "`n")) {
    if (-not $line.Trim()) { continue }
    $parts = $line -split "`t", 3
    if ($parts.Count -lt 3) { continue }
    $count++
    if ($parts[0] -match '^\d+$') { $adds += [int]$parts[0]; $dels += [int]$parts[1] }
    if ($fileRows.Count -lt 300) {
        $a = if ($parts[0] -eq "-") { "binary" } else { $parts[0] }
        $fileRows += "| ``$($parts[2])`` | $a | $($parts[1]) |"
    }
}
if ($count -gt 300) { $fileRows += "| ($($count - 300) more: run the Changed files command) | | |" }
if ($count -eq 0) { $fileRows += "| (no changes) | | |" }
$commits = (Invoke-Git @("-C", $repoPath, "rev-list", "--count", "$mb..$src")).Out

# ------------------------------------------------------------------ issues it closes
$wiText = "None linked (no ""Fixes #<n>"" in the PR)."
try {
    $q = 'query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){closingIssuesReferences(first:5){totalCount nodes{number title state body repository{nameWithOwner} labels(first:20){nodes{name}}}}}}}'
    $g = Invoke-GitHubGraphQl $h $q @{ owner = $owner; name = $name; number = $prId }
    $refs = $g.repository.pullRequest.closingIssuesReferences
    $blocks = foreach ($i in @($refs.nodes)) {
        if (-not $i) { continue }
        $parts = Split-GitHubBody "$($i.body)"
        $desc = $parts.Description
        if ($desc.Length -gt 3000) { $desc = $desc.Substring(0, 3000) + " ..." }
        $type = Get-GitHubType @($i.labels.nodes | ForEach-Object { $_.name })
        $b = "### $($i.repository.nameWithOwner)#$($i.number) ${type}: $($i.title) ($($i.state))`n`nAcceptance criteria:`n`n$(if ($parts.AcceptanceCriteria) { $parts.AcceptanceCriteria } else { 'None provided' })`n`nDescription:`n`n$(if ($desc) { $desc } else { 'None provided' })"
        if ($parts.ReproSteps) { $b += "`n`nRepro steps:`n`n$($parts.ReproSteps)" }
        $b
    }
    if (@($blocks).Count) {
        $wiText = (@($blocks) -join "`n`n")
        if ($refs.totalCount -gt 5) { $wiText += "`n`n($($refs.totalCount - 5) more linked; only the first 5 are shown.)" }
    }
}
catch { $wiText = "Could not fetch linked issues: $($_.Exception.Message)" }

# ------------------------------------------------------------------ existing comments
$threadLines = @()
$clip = { param($t) $s = ("$t" -replace "\r?\n", " ").Trim(); if ($s.Length -gt 600) { $s.Substring(0, 600) + " ..." } else { $s } }
try {
    $general = @(Invoke-GitHubRest $h "/repos/$repoFull/issues/$prId/comments?per_page=100" "the PR's comments") | Where-Object { $_ -and "$($_.body)".Trim() }
    $reviews = @(Invoke-GitHubRest $h "/repos/$repoFull/pulls/$prId/reviews?per_page=100" "the PR's reviews") | Where-Object { $_ -and "$($_.body)".Trim() }
    if (@($general).Count -or @($reviews).Count) {
        $threadLines += "### General"
        $threadLines += ""
        foreach ($c in @($reviews)) { $threadLines += "- $($c.user.login) ($("$($c.state)".ToLowerInvariant() -replace '_', ' ')): $(& $clip $c.body)" }
        foreach ($c in @($general)) { $threadLines += "- $($c.user.login): $(& $clip $c.body)" }
        $threadLines += ""
    }
    $lineComments = @(Invoke-GitHubRest $h "/repos/$repoFull/pulls/$prId/comments?per_page=100" "the PR's line comments") | Where-Object { $_ }
    foreach ($grp in ($lineComments | Group-Object { "$($_.path):$(if ($_.line) { $_.line } else { $_.original_line })" })) {
        $threadLines += "### ``$($grp.Name)``"
        $threadLines += ""
        foreach ($c in $grp.Group) { $threadLines += "- $($c.user.login): $(& $clip $c.body)" }
        $threadLines += ""
    }
}
catch { $threadLines = @("Could not fetch comments: $($_.Exception.Message)") }
if ($threadLines.Count -eq 0) { $threadLines = @("No comments yet.") }

# ------------------------------------------------------------------ write the folder
$folder = Join-Path $WorkRoot "pr-$prId"
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$reviewNote = "No earlier review."
$reviewPath = Join-Path $folder "review.md"
if (Test-Path $reviewPath) {
    $old = Get-Content $reviewPath -Raw
    $oldSha = if ($old -match '(?m)^Reviewed commit:\s*([0-9a-f]{7,40})') { $Matches[1] } else { $null }
    if ($oldSha -and $src.StartsWith($oldSha)) {
        $reviewNote = "ALREADY: review.md already covers this commit ($($src.Substring(0,7)))."
    }
    else {
        $hist = Join-Path $folder "history"
        New-Item -ItemType Directory -Path $hist -Force | Out-Null
        $label = if ($oldSha) { $oldSha.Substring(0, [Math]::Min(7, $oldSha.Length)) } else { (Get-Date).ToString("yyyyMMdd-HHmmss") }
        Move-Item -LiteralPath $reviewPath -Destination (Join-Path $hist "review-$label.md") -Force
        $reviewNote = "The earlier review (commit $label) moved to history/review-$label.md. New commits since then."
    }
}

$latest = @{}
foreach ($rv in @(Invoke-GitHubRest $h "/repos/$repoFull/pulls/$prId/reviews?per_page=100" "the PR's reviews")) {
    if ($rv -and $rv.user -and "$($rv.state)" -ne "COMMENTED") { $latest[$rv.user.login] = "$($rv.state)".ToLowerInvariant() -replace '_', ' ' }
}
$asked = @($pr.requested_reviewers | ForEach-Object { "$($_.login) (asked, no review yet)" }) + @($pr.requested_teams | ForEach-Object { "team $($_.slug) (asked)" })
$reviewers = (@($latest.Keys | ForEach-Object { "$_ ($($latest[$_]))" }) + $asked) -join "; "
if (-not $reviewers) { $reviewers = "None" }
$desc = [string]$pr.body
if (-not $desc.Trim()) { $desc = "None provided" }
$status = if ($pr.merged) { "merged" } elseif ("$($pr.state)" -eq "closed") { "closed" } else { "open" }
$today = (Get-Date).ToString("yyyy-MM-dd")
$s7 = $src.Substring(0, 7)
$m7 = $mb.Substring(0, 7)
$notes = @($repoNote, $moved) | Where-Object { $_ }
$notesText = if ($notes) { ($notes | ForEach-Object { "- $_" }) -join "`n" } else { "- None" }

$md = @"
# Pull request ${prId}: $($pr.title)

- Repo: $repoFull (folder ``$folderName``)
- Author: $($pr.user.login)
- Branch: $($pr.head.ref) -> $targetRef
- Status: $status$(if ($pr.draft) { ', draft' })
- Link: $webLink
- GitHub: $repoFull#$prId
- Fetched: $today, from refs/pull/$prId/head and $targetRef
- Source commit: $src
- Merge base: $mb
- Size: $count files, +$adds -$dels, $commits commits
- Reviewers: $reviewers

## Read the code with

The repo folder is on whatever branch the engineer has checked out, not the PR. Never open the PR's files from disk. Use these commands, exactly:

| What | Command |
|---|---|
| Changed files | ``git -C $folderName diff --stat $m7 $s7`` |
| Whole diff | ``git -C $folderName diff $m7 $s7`` |
| One file's diff | ``git -C $folderName diff $m7 $s7 -- <path>`` |
| A whole file as of the PR | ``git -C $folderName show $($s7):<path>`` |
| The same file before the PR | ``git -C $folderName show $($m7):<path>`` |
| Find text in the PR's code | ``git -C $folderName grep -n "<text>" $s7`` |
| Commits | ``git -C $folderName log --oneline $m7..$s7`` |

## Notes

$notesText

## Changed files

| File | + | - |
|---|---|---|
$($fileRows -join "`n")

## Description

$desc

## Linked work items

$wiText
"@

Write-GitHubUtf8 (Join-Path $folder "context.md") $md
Write-GitHubUtf8 (Join-Path $folder "threads.md") ("# Existing comments: pull request $prId`n`nAlready raised on the PR. Do not suggest these again.`n`n" + ($threadLines -join "`n") + "`n")

Write-Output "Fetched PR $repoFull#$prId from GitHub: $($pr.title) ($count files, +$adds -$dels) in $folderName"
Write-Output $reviewNote
Write-Output (Resolve-Path $folder).Path
