<#
.SYNOPSIS
    Fetches an Azure DevOps pull request for a first-pass review and writes .work/pr-<id>/.

.DESCRIPTION
    Read-only against ADO: it only makes GET calls. It never posts comments or votes.

    1. Reads the PR, its linked work items, and its comment threads from ADO Server over REST.
    2. Finds the PR's repo among the folders in the workspace (by git remote, else by folder name).
    3. Fetches the PR's source and target branches into private refs
       (refs/eng-agents/pr/<id>/source and .../target). It does not check anything out,
       so the engineer's working tree and branches are not touched.
    4. Writes .work/pr-<id>/context.md (what the PR is, the exact git commands to read it,
       changed files, description, linked work items) and threads.md (existing comments).

    Running it again refreshes both files. If review.md exists for an older source commit,
    it is moved to history/review-<old commit>.md. A review of the same commit is kept.

    The LAST line of output is always the folder path. Lines starting with one of these
    words explain a failure, so the calling agent can act on it:
      AMBIGUOUS: / UNKNOWN:  which ADO connection to use is not clear
      NOCONN:                the PR link matches no connection in config.json
      NOREPO:                the PR's repo is not cloned in the workspace
      FETCH:                 git could not fetch the PR's branches

    Settings come from config.json (see config.example.json). The PAT comes from an
    environment variable (ADO_PAT unless the connection sets patEnv) and is never written
    to disk. It needs Code (Read) and Work Items (Read).

.EXAMPLE
    .\Get-PullRequest.ps1 -Url "https://ado.example.local/tfs/DefaultCollection/Shop/_git/orders-api/pullrequest/812"

.EXAMPLE
    .\Get-PullRequest.ps1 -Id 812 -From orders-api

.EXAMPLE
    .\Get-PullRequest.ps1 -Url "<pr link>" -ShowConnection
#>
[CmdletBinding()]
param(
    # The PR's web link, as copied from ADO.
    [string]$Url,

    # The PR number. Needs -From (or a default connection) to know the server.
    [int]$Id,

    [string]$WorkRoot = ".work",

    # The folder that holds the repos. Default: the parent of WorkRoot.
    [string]$Workspace,

    [string]$ConfigPath = (Join-Path $(if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }) ".config/eng-agents/config.json"),

    # A connection name from config.json, or a repo folder whose path or git remote
    # identifies the connection. Only used with -Id.
    [string]$From,

    # Print which connection would be used and why, then exit. Calls nothing.
    [switch]$ShowConnection
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "AdoConnection.ps1")

if (-not $Url -and -not $Id) { throw "Give the PR link (-Url) or its number (-Id)." }

$cfg = Read-AdoConfig $ConfigPath
$prId = $Id
if ($Url) {
    if ($Url -notmatch '(?i)/pullrequest/(\d+)') { throw "That is not a pull request link: $Url. It should end in /pullrequest/<number>." }
    $prId = [int]$Matches[1]
    $m = Find-AdoUrlMapping $cfg $Url
    if (-not $m -or -not $m.Name) { throw "NOCONN: the link matches no connection's serverUrl + collection in $ConfigPath. Connections: $($cfg.NamesText)" }
    $conn = Get-AdoConnection $cfg $m.Name
    $conn.Reason = "PR link"
    if ($m.Project) { $conn.Project = $m.Project }
}
else {
    $conn = Resolve-AdoConnection $cfg $From
}

if ($ShowConnection) {
    Write-AdoConnectionInfo $conn "(not needed: the PR says which project it is in)"
    Write-Output "Pull request: $prId"
    exit 0
}

$request = New-AdoRequest $conn
$api = $conn.ApiVersion
$base = $conn.Base

function Invoke-Ado {
    param([string]$Path, [string]$What)
    $r = $request.Clone()
    $sep = if ($Path.Contains("?")) { "&" } else { "?" }
    $r.Uri = "$base/$Path$($sep)api-version=$api"
    try { return Invoke-RestMethod @r }
    catch { throw "ADO request failed for $What on connection '$($conn.Name)' ($base). $($_.Exception.Message)" }
}

function Esc([string]$s) { return [System.Uri]::EscapeDataString($s) }

function Get-RefName([string]$ref) { return ($ref -replace '^refs/heads/', '') }

function Get-VoteText($v) {
    switch ([int]$v) {
        10 { return "approved" }
        5 { return "approved with suggestions" }
        -5 { return "waiting for author" }
        -10 { return "rejected" }
        default { return "no vote" }
    }
}

function Invoke-Git {
    # Returns { Code, Out }. No terminal prompts; credential helpers still work.
    param([string[]]$GitArgs)
    $old = $env:GIT_TERMINAL_PROMPT
    $env:GIT_TERMINAL_PROMPT = "0"
    # Windows PowerShell 5.1 turns native stderr into errors under "Stop" when it is redirected.
    $ErrorActionPreference = "Continue"
    try {
        $out = & git @GitArgs 2>&1
        return [pscustomobject]@{ Code = $LASTEXITCODE; Out = (($out | ForEach-Object { "$_" }) -join "`n").Trim() }
    }
    finally { $env:GIT_TERMINAL_PROMPT = $old }
}

# ------------------------------------------------------------------ the PR
$pr = Invoke-Ado "_apis/git/pullrequests/$prId" "pull request $prId"
$repoObj = $pr.repository
$repoName = [string]$repoObj.name
$project = [string](Get-AdoProp (Get-AdoProp $repoObj "project") "name")
if (-not $project) { $project = $conn.Project }
$repoId = [string]$repoObj.id
$remoteUrl = [string](Get-AdoProp $repoObj "remoteUrl")
$webLink = $(if (Get-AdoProp $repoObj "webUrl") { "$($repoObj.webUrl)/pullrequest/$prId" } else { "$base/$(Esc $project)/_git/$(Esc $repoName)/pullrequest/$prId" })
$sourceRef = [string]$pr.sourceRefName
$targetRef = [string]$pr.targetRefName
$apiSource = [string](Get-AdoProp (Get-AdoProp $pr "lastMergeSourceCommit") "commitId")
$repoApi = "$(Esc $project)/_apis/git/repositories/$repoId/pullRequests/$prId"

# ------------------------------------------------------------------ the local repo
if (-not $Workspace) {
    $wr = if ([System.IO.Path]::IsPathRooted($WorkRoot)) { $WorkRoot } else { Join-Path (Get-Location).Path $WorkRoot }
    $Workspace = Split-Path -Parent ([System.IO.Path]::GetFullPath($wr))
}
$repoDirs = @(Get-ChildItem -LiteralPath $Workspace -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName ".git") })
$repoDir = $null
$remoteKey = if ($remoteUrl) { ConvertTo-AdoUrlKey $remoteUrl } else { $null }
$tail = "/_git/" + $repoName.ToLowerInvariant()
foreach ($d in $repoDirs) {
    $r = Get-AdoRemoteUrl $d.FullName
    if (-not $r) { continue }
    $k = ConvertTo-AdoUrlKey $r
    if (($remoteKey -and $k -eq $remoteKey) -or $k.EndsWith($tail) -or $k.EndsWith("/" + [System.Uri]::EscapeDataString($repoName).ToLowerInvariant())) { $repoDir = $d; break }
}
$repoNote = $null
if (-not $repoDir) {
    $repoDir = $repoDirs | Where-Object { $_.Name -ieq $repoName } | Select-Object -First 1
    if ($repoDir) { $repoNote = "Matched by folder name only: the folder's git remote does not point at this repo." }
}
if (-not $repoDir) {
    throw "NOREPO: $repoName is not cloned in the workspace ($Workspace). Clone it there$(if ($remoteUrl) { " ($remoteUrl)" }), then run this again."
}
$folderName = $repoDir.Name
$repoPath = $repoDir.FullName

# ------------------------------------------------------------------ fetch, no checkout
$ns = "refs/eng-agents/pr/$prId"
$f = Invoke-Git @("-C", $repoPath, "fetch", "--no-tags", "--quiet", "origin", "+$($sourceRef):$ns/source", "+$($targetRef):$ns/target")
$how = "source and target branches"
if ($f.Code -ne 0) {
    # A PR from a fork has no source branch on origin. ADO's merge ref has the target as its first
    # parent and the source as its second.
    $g = Invoke-Git @("-C", $repoPath, "fetch", "--no-tags", "--quiet", "origin", "+refs/pull/$prId/merge:$ns/merge")
    if ($g.Code -ne 0) { throw "FETCH: git could not fetch the PR's branches in $folderName. $($f.Out)" }
    [void](Invoke-Git @("-C", $repoPath, "update-ref", "$ns/source", "$ns/merge^2"))
    [void](Invoke-Git @("-C", $repoPath, "update-ref", "$ns/target", "$ns/merge^1"))
    $how = "ADO's merge ref (the source branch is not on origin)"
}
$src = (Invoke-Git @("-C", $repoPath, "rev-parse", "$ns/source")).Out
$tgt = (Invoke-Git @("-C", $repoPath, "rev-parse", "$ns/target")).Out
$mbr = Invoke-Git @("-C", $repoPath, "merge-base", $tgt, $src)
if ($mbr.Code -ne 0) { throw "FETCH: no common history between the PR's branches in $folderName (a shallow clone?). Run git -C $folderName fetch --unshallow, then try again." }
$mb = $mbr.Out
$moved = $null
if ($apiSource -and $src -ne $apiSource) { $moved = "The source branch moved after ADO's last merge check; this review reads $($src.Substring(0,7)), the branch as fetched." }

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

# ------------------------------------------------------------------ linked work items
$wiText = "None linked."
try {
    $refs = Invoke-Ado "$repoApi/workitems" "the PR's work items"
    $ids = @($refs.value | ForEach-Object { $_.id } | Select-Object -First 5)
    if ($ids.Count -gt 0) {
        $fields = "System.Id,System.Title,System.WorkItemType,System.State,System.Description,Microsoft.VSTS.Common.AcceptanceCriteria,Microsoft.VSTS.TCM.ReproSteps"
        $wis = Invoke-Ado "_apis/wit/workitems?ids=$($ids -join ',')&fields=$fields" "work items $($ids -join ', ')"
        $blocks = foreach ($w in $wis.value) {
            $fl = $w.fields
            $ac = ConvertFrom-AdoHtml (Get-AdoProp $fl "Microsoft.VSTS.Common.AcceptanceCriteria")
            $desc = ConvertFrom-AdoHtml (Get-AdoProp $fl "System.Description")
            $repro = ConvertFrom-AdoHtml (Get-AdoProp $fl "Microsoft.VSTS.TCM.ReproSteps")
            if ($desc.Length -gt 3000) { $desc = $desc.Substring(0, 3000) + " ..." }
            $b = "### #$($w.id) $(Get-AdoProp $fl 'System.WorkItemType'): $(Get-AdoProp $fl 'System.Title') ($(Get-AdoProp $fl 'System.State'))`n`nAcceptance criteria:`n`n$(if ($ac) { $ac } else { 'None provided' })`n`nDescription:`n`n$(if ($desc) { $desc } else { 'None provided' })"
            if ($repro) { $b += "`n`nRepro steps:`n`n$repro" }
            $b
        }
        $wiText = ($blocks -join "`n`n")
        if (@($refs.value).Count -gt 5) { $wiText += "`n`n($(@($refs.value).Count - 5) more linked; only the first 5 are shown.)" }
    }
}
catch { $wiText = "Could not fetch linked work items: $($_.Exception.Message)" }

# ------------------------------------------------------------------ existing threads
$threadLines = @()
try {
    $threads = Invoke-Ado "$repoApi/threads" "the PR's comment threads"
    foreach ($t in $threads.value) {
        if ($t.isDeleted) { continue }
        $cs = @($t.comments | Where-Object { -not $_.isDeleted -and $_.commentType -ne "system" -and $_.content })
        if ($cs.Count -eq 0) { continue }
        $ctx = Get-AdoProp $t "threadContext"
        $where = "General"
        if ($ctx -and $ctx.filePath) {
            $start = Get-AdoProp $ctx "rightFileStart"
            if (-not $start) { $start = Get-AdoProp $ctx "leftFileStart" }
            $where = "``$($ctx.filePath.TrimStart('/'))$(if ($start) { ':' + $start.line })``"
        }
        $status = if ($t.status) { $t.status } else { "none" }
        $threadLines += "### $where ($status)"
        $threadLines += ""
        foreach ($c in $cs) {
            $text = ([string]$c.content -replace "\r?\n", " ").Trim()
            if ($text.Length -gt 600) { $text = $text.Substring(0, 600) + " ..." }
            $threadLines += "- $(Get-AdoProp $c.author 'displayName'): $text"
        }
        $threadLines += ""
    }
}
catch { $threadLines = @("Could not fetch threads: $($_.Exception.Message)") }
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
        $dest = Join-Path $hist "review-$label.md"
        Move-Item -LiteralPath $reviewPath -Destination $dest -Force
        $reviewNote = "The earlier review (commit $label) moved to history/review-$label.md. New commits since then."
    }
}

$reviewers = @($pr.reviewers | Where-Object { $_ } | ForEach-Object {
    "$($_.displayName) ($(if ($_.isRequired) { 'required' } else { 'optional' }), $(Get-VoteText $_.vote))"
}) -join "; "
if (-not $reviewers) { $reviewers = "None" }
$desc = [string]$pr.description
if (-not $desc.Trim()) { $desc = "None provided" }
$today = (Get-Date).ToString("yyyy-MM-dd")
$s7 = $src.Substring(0, 7)
$m7 = $mb.Substring(0, 7)
$notes = @($repoNote, $moved) | Where-Object { $_ }
$notesText = if ($notes) { ($notes | ForEach-Object { "- $_" }) -join "`n" } else { "- None" }

$md = @"
# Pull request ${prId}: $($pr.title)

- Repo: $repoName (folder ``$folderName``)
- Author: $(Get-AdoProp $pr.createdBy 'displayName')
- Branch: $(Get-RefName $sourceRef) -> $(Get-RefName $targetRef)
- Status: $($pr.status)$(if ($pr.isDraft) { ', draft' })
- Link: $webLink
- ADO: $($conn.Name) ($($conn.Collection)/$project)
- Fetched: $today, from $how
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

Write-AdoUtf8 (Join-Path $folder "context.md") $md
Write-AdoUtf8 (Join-Path $folder "threads.md") ("# Existing comments: pull request $prId`n`nAlready raised on the PR. Do not suggest these again.`n`n" + ($threadLines -join "`n") + "`n")

Write-Output "Fetched PR $prId from '$($conn.Name)': $($pr.title) ($count files, +$adds -$dels) in $folderName"
Write-Output $reviewNote
Write-Output (Resolve-Path $folder).Path
