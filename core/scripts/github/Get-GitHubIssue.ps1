<#
.SYNOPSIS
    Fetches a GitHub issue for /start and writes it as a local work item: .work/L<n>-<short-name>/workitem.md.

.DESCRIPTION
    Read-only against GitHub: GET calls and one GraphQL query (the sub-issue parent). It never comments or
    changes the issue.

    A GitHub issue becomes a local work item (L1, L2, ...), the same folders New-LocalWorkItem.ps1 makes, so the
    rest of the pipeline and Dispatch need nothing new. workitem.md says where it came from:
      - GitHub: owner/repo#12
      - Link: https://github.com/owner/repo/issues/12
    and has the issue's body (split into Description, Acceptance criteria and Repro steps by their ## headings),
    labels, milestone (the Epic: a major version), sub-issue parent (the Feature) and comments.

    The LAST line of output is always the folder path. Lines starting with one of these words explain a failure:
      ALREADY:   a work item for this issue already exists (the folder is named)
      BADID:     not owner/repo#number, and no repo to go with a bare number
      NOTFOUND:  GitHub has no such issue, or the token cannot see it
      NOTOKEN:   no GitHub token (see GitHubCommon.ps1)

.EXAMPLE
    .\Get-GitHubIssue.ps1 -Id "acme/web#12" -WorkRoot .work -IncludeComments

.EXAMPLE
    .\Get-GitHubIssue.ps1 -Id 12 -From web -WorkRoot .work
    A bare number: the repo comes from the git remote of the workspace folder "web".

.EXAMPLE
    .\Get-GitHubIssue.ps1 -Id "acme/web#12" -IssueJson issue.json
    Offline (tests): the issue, and optionally "parent" and "comments", from a JSON file shaped like GitHub's REST answer.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Id,

    [string]$WorkRoot = ".work",

    # With a bare number: a repo folder in the workspace (its git remote names the repo), or owner/repo.
    [string]$From,

    [switch]$IncludeComments,

    # Tests only: read the issue from this file instead of GitHub.
    [string]$IssueJson
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "GitHubCommon.ps1")

# ------------------------------------------------------------------ which issue
$ref = ConvertFrom-GitHubIssueId $Id
if (-not $ref -and "$Id".TrimStart("#") -match '^\d{1,9}$') {
    $repo = $null
    if ($From -and $From -match '^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}$') { $repo = $From }
    elseif ($From) {
        $wr = if ([System.IO.Path]::IsPathRooted($WorkRoot)) { $WorkRoot } else { Join-Path (Get-Location).Path $WorkRoot }
        $ws = Split-Path -Parent ([System.IO.Path]::GetFullPath($wr))
        $dir = if ([System.IO.Path]::IsPathRooted($From)) { $From } else { Join-Path $ws $From }
        if (Test-Path (Join-Path $dir ".git")) {
            $ErrorActionPreference = "Continue"
            $remote = (& git -C $dir remote get-url origin 2>$null | Select-Object -First 1)
            $ErrorActionPreference = "Stop"
            $repo = ConvertFrom-GitHubRemote $remote
        }
    }
    if ($repo) { $ref = @{ Repo = $repo; Number = [int]("$Id".TrimStart("#")) } }
}
if (-not $ref) { throw "BADID: give the issue as owner/repo#number, or a number with -From <repo folder or owner/repo>." }
$key = "$($ref.Repo)#$($ref.Number)"

# ------------------------------------------------------------------ already started?
if (Test-Path $WorkRoot) {
    foreach ($d in @(Get-ChildItem -LiteralPath $WorkRoot -Directory -ErrorAction SilentlyContinue)) {
        $f = Join-Path $d.FullName "workitem.md"
        if (-not (Test-Path $f)) { continue }
        $t = [System.IO.File]::ReadAllText($f)
        if ($t -match ("(?m)^- GitHub: " + [regex]::Escape($key) + "\s*$")) {
            Write-Output "ALREADY: $key is already started in $($d.Name)."
            Write-Output $d.FullName
            exit 1
        }
    }
}

# ------------------------------------------------------------------ the issue
$parent = $null
$comments = @()
if ($IssueJson) {
    $raw = [System.IO.File]::ReadAllText((Resolve-Path $IssueJson).Path) | ConvertFrom-Json
    $issue = $raw
    if ($raw.PSObject.Properties.Name -contains "parent") { $parent = $raw.parent }
    if ($raw.PSObject.Properties.Name -contains "comments_list") { $comments = @($raw.comments_list) }
}
else {
    $h = New-GitHubHeaders
    $issue = Invoke-GitHubRest $h "/repos/$($ref.Repo)/issues/$($ref.Number)" "issue $key"
    if ($issue.PSObject.Properties.Name -contains "pull_request" -and $issue.pull_request) { throw "BADID: $key is a pull request, not an issue. Use /pr-review for pull requests." }
    try {
        $owner, $name = $ref.Repo -split "/", 2
        $q = 'query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){issue(number:$number){parent{number title url state repository{nameWithOwner} labels(first:20){nodes{name}}}}}}'
        $g = Invoke-GitHubGraphQl $h $q @{ owner = $owner; name = $name; number = $ref.Number }
        $parent = $g.repository.issue.parent
    }
    catch { $parent = "unknown: $($_.Exception.Message)" }
    if ($IncludeComments) {
        try { $comments = @(Invoke-GitHubRest $h "/repos/$($ref.Repo)/issues/$($ref.Number)/comments?per_page=100" "comments on $key") }
        catch { $comments = "Could not fetch comments: $($_.Exception.Message)" }
    }
}

$labels = @($issue.labels | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } } | Where-Object { $_ })
$type = Get-GitHubType $labels
$title = ("$($issue.title)" -replace "[\r\n]+", " ").Trim()
if (-not $title) { $title = "GitHub issue $key" }
$state = if ("$($issue.state)" -eq "closed") { "Closed" } else { "Open" }
$link = "$($issue.html_url)"
$body = Split-GitHubBody "$($issue.body)"
$description = if ($body.Description) { $body.Description } else { "None provided" }
$criteria = if ($body.AcceptanceCriteria) { $body.AcceptanceCriteria } else { "None provided" }
$repro = if ($body.ReproSteps) { $body.ReproSteps } elseif ($type -eq "Bug") { "See the description" } else { "Not a bug" }
$milestone = if ($issue.milestone) { "$($issue.milestone.title)" } else { "" }
$today = (Get-Date).ToString("yyyy-MM-dd")

# Parents, nearest first: the sub-issue parent (the Feature), then the milestone (the Epic, a major version).
$parentLines = @()
if ($parent -is [string]) { $parentLines += "Parent issue unknown: $parent" }
elseif ($parent) {
    $pLabels = @($parent.labels.nodes | ForEach-Object { $_.name })
    $pType = Get-GitHubType $pLabels
    if ($pType -eq "Issue") { $pType = "Feature" }
    $parentLines += "- ${pType}: $($parent.repository.nameWithOwner)#$($parent.number) $($parent.title)"
}
if ($milestone) { $parentLines += "- Epic (milestone): $milestone" }
$parentsText = if ($parentLines.Count) { $parentLines -join "`n" } else { "None (no parent issue and no milestone)" }

if ($comments -is [string]) { $commentsText = $comments }
elseif (-not $IncludeComments -and -not $IssueJson) { $commentsText = "Not fetched (use -IncludeComments)" }
else {
    $lines = foreach ($c in @($comments)) { if ($c -and "$($c.body)".Trim()) { "- $($c.user.login): " + (("$($c.body)" -replace "\r?\n", " ").Trim()) } }
    $commentsText = if ($lines) { @($lines) -join "`n" } else { "None" }
}

# ------------------------------------------------------------------ the folder: a local work item
$localType = if ($type -eq "Bug") { "Bug" } else { "Feature" }
$out = & (Join-Path $PSScriptRoot "../work/New-LocalWorkItem.ps1") -WorkRoot $WorkRoot -Title $title -Type $localType
$folder = @($out)[-1]
$localId = (Split-Path -Leaf $folder) -replace '-.*$', ''

$md = @"
# Work item ${localId}: $title

- Type: $type
- State: $state
- Source: GitHub issue (fetched into a local work item)
- GitHub: $key
- Labels: $(if ($labels.Count) { $labels -join ', ' } else { 'None' })
- Milestone: $(if ($milestone) { $milestone } else { 'None' })
- Link: $link
- Fetched: $today

## Description

$description

## Acceptance criteria

$criteria

## Repro steps (bugs only)

$repro

## Parents

Nearest first.

$parentsText

## Comments

$commentsText

## Extra context from the engineer

<anything else>
"@

Write-GitHubUtf8 (Join-Path $folder "workitem.md") $md
Write-Output "Fetched GitHub issue $key ($type) as local work item ${localId}: $title"
Write-Output $folder
