<#
.SYNOPSIS
    Fetches an Azure DevOps work item and creates its pipeline folder under .work.

.DESCRIPTION
    Online mode (default): reads the work item from ADO Server over REST and writes
    <WorkRoot>\<Id>-<short-name>\workitem.md.

    Offline mode (-Title): skips ADO and creates the same folder with an empty
    workitem.md for the engineer to paste into.

    The LAST line of output is always the folder path, so the calling agent can use it.

    Settings come from config.json (see config.example.json). The PAT comes from an
    environment variable (ADO_PAT unless the connection sets patEnv) and is never
    written to disk.

    Several ADO servers or project collections are supported. The script picks one
    connection, in this order:
      1. -From <connection name>
      2. -From <repo folder>: a "paths" mapping that matches the repo's full path,
         otherwise the collection in the repo's git remote URL
      3. A "paths" mapping that matches the current folder
      4. The "default" connection
      5. The only connection, if there is just one
    If none of these decide, it fails with a line starting "AMBIGUOUS:" that lists
    the connection names.

.EXAMPLE
    .\Get-WorkItem.ps1 -Id 12345 -WorkRoot .work

.EXAMPLE
    .\Get-WorkItem.ps1 -Id 12345 -WorkRoot .work -Title "Export job fails on retry"

.EXAMPLE
    .\Get-WorkItem.ps1 -Id 12345 -WorkRoot .work -From orders-api

.EXAMPLE
    .\Get-WorkItem.ps1 -Id 12345 -WorkRoot .work -Parents
    Also writes a "Parents" section: the parent Feature, its Epic, and so on up.

.EXAMPLE
    .\Get-WorkItem.ps1 -Id 0 -From orders-api -ShowConnection
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [int]$Id,

    [string]$WorkRoot = ".work",

    # Offline mode: create the folder from this title without calling ADO.
    [string]$Title,

    [string]$ConfigPath = (Join-Path $(if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }) ".config/eng-agents/config.json"),

    # Also fetch comments. Uses a preview API that some ADO Server versions lack.
    [switch]$IncludeComments,

    # Also fetch the parents up the hierarchy (Story, then Feature, then Epic): id, type and title.
    # A failure is written into workitem.md; the script still succeeds.
    [switch]$Parents,

    # A connection name from config.json, or a repo folder whose path or git remote
    # identifies the connection.
    [string]$From,

    # Print which connection would be used and why, then exit. Calls nothing.
    [switch]$ShowConnection
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "AdoConnection.ps1")

function ConvertTo-Slug {
    param([string]$Text)
    $stop = @("a", "an", "the", "to", "of", "for", "and", "or", "in", "on", "at", "with", "is", "be", "when", "from", "by")
    $words = ($Text.ToLowerInvariant() -replace "[^a-z0-9 ]", " ") -split "\s+" |
        Where-Object { $_ -and ($stop -notcontains $_) }
    $slug = (@($words) | Select-Object -First 5) -join "-"
    if ($slug.Length -gt 40) { $slug = $slug.Substring(0, 40).TrimEnd("-") }
    if (-not $slug) { $slug = "item" }
    return $slug
}

function Get-Field {
    param($Fields, [string]$Name)
    $p = $Fields.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

function Write-Utf8 {
    param([string]$Path, [string]$Content)
    Write-AdoUtf8 $Path $Content
}

function New-WorkFolder {
    param([string]$ItemTitle)
    $slug = ConvertTo-Slug $ItemTitle
    $folder = Join-Path $WorkRoot "$Id-$slug"
    if (Test-Path $folder) { throw "Folder already exists: $folder" }
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    return $folder
}

$today = (Get-Date).ToString("yyyy-MM-dd")

# ---------------------------------------------------------------- offline mode
if ($Title) {
    $folder = New-WorkFolder $Title
    $md = @"
# Work item ${Id}: $Title

- Type: <Bug | User Story | Feature | Task>
- State: <state>
- Link: <paste the work item URL from ADO>
- Fetched: Pasted by engineer on $today

## Description

<paste the description here>

## Acceptance criteria

<paste acceptance criteria here, or "None provided">

## Repro steps (bugs only)

<paste repro steps here, or "Not a bug">

## Extra context from the engineer

<anything else>
"@
    Write-Utf8 (Join-Path $folder "workitem.md") $md
    Write-Output "Created offline work item. Paste the details into workitem.md."
    Write-Output (Resolve-Path $folder).Path
    exit 0
}

# ----------------------------------------------------------------- online mode
$cfg = Read-AdoConfig $ConfigPath " Or use -Title for offline mode."
$conn = Resolve-AdoConnection $cfg $From
$base = $conn.Base

if ($ShowConnection) {
    Write-AdoConnectionInfo $conn "(not set; only needed for -IncludeComments)"
    exit 0
}

$request = New-AdoRequest $conn " Set it, or use -Title for offline mode."

$request.Uri = "$base/_apis/wit/workitems/$($Id)?`$expand=relations&api-version=$($conn.ApiVersion)"

try {
    $item = Invoke-RestMethod @request
}
catch {
    throw "ADO request failed for work item $Id on connection '$($conn.Name)' ($base). $($_.Exception.Message)"
}

$f = $item.fields
$itemTitle = Get-Field $f "System.Title"
$type = Get-Field $f "System.WorkItemType"
$state = Get-Field $f "System.State"
$area = Get-Field $f "System.AreaPath"
$iteration = Get-Field $f "System.IterationPath"
$tags = Get-Field $f "System.Tags"
$description = ConvertFrom-AdoHtml (Get-Field $f "System.Description")
$criteria = ConvertFrom-AdoHtml (Get-Field $f "Microsoft.VSTS.Common.AcceptanceCriteria")
$repro = ConvertFrom-AdoHtml (Get-Field $f "Microsoft.VSTS.TCM.ReproSteps")

if (-not $description) { $description = "None provided" }
if (-not $criteria) { $criteria = "None provided" }
if (-not $repro) { $repro = "Not provided" }

$related = @()
if ($item.relations) {
    foreach ($r in $item.relations) {
        $name = if ($r.attributes -and $r.attributes.name) { $r.attributes.name } else { $r.rel }
        if ($r.url -match "/workItems/(\d+)$") { $related += "- ${name}: #$($Matches[1])" }
    }
}
$relatedText = if ($related.Count -gt 0) { $related -join "`n" } else { "None" }

function Get-ParentId {
    # The id of an item's parent (the Hierarchy-Reverse link), or $null.
    param($WorkItem)
    foreach ($r in @($WorkItem.relations)) {
        if ($r -and $r.rel -eq "System.LinkTypes.Hierarchy-Reverse" -and $r.url -match "/workItems/(\d+)$") { return [int]$Matches[1] }
    }
    return $null
}

$parentsText = $null
if ($Parents) {
    # Walk up one parent at a time. Stop at the top, at 5 levels, or at a loop.
    $chain = @()
    $seen = @($Id)
    $parentId = Get-ParentId $item
    try {
        while ($parentId -and $chain.Count -lt 5 -and ($seen -notcontains $parentId)) {
            $seen += $parentId
            $p = $request.Clone()
            $p.Uri = "$base/_apis/wit/workitems/$($parentId)?`$expand=relations&api-version=$($conn.ApiVersion)"
            $parent = Invoke-RestMethod @p
            $pType = Get-Field $parent.fields "System.WorkItemType"
            $pTitle = Get-Field $parent.fields "System.Title"
            $chain += "- ${pType}: #$parentId $pTitle"
            $parentId = Get-ParentId $parent
        }
        $parentsText = if ($chain.Count -gt 0) { $chain -join "`n" } else { "None (this item has no parent)" }
    }
    catch {
        $got = if ($chain.Count -gt 0) { ($chain -join "`n") + "`n" } else { "" }
        $parentsText = $got + "Parents unknown: could not fetch work item #$parentId. $($_.Exception.Message)"
    }
}
# Empty without -Parents, so workitem.md is unchanged.
$parentsBlock = if ($null -ne $parentsText) { "`n`n## Parents`n`nNearest first.`n`n$parentsText" } else { "" }

$commentsText = "Not fetched (use -IncludeComments)"
if ($IncludeComments -and -not $conn.Project) {
    $commentsText = "Not fetched: connection '$($conn.Name)' has no 'project' in config.json"
}
elseif ($IncludeComments) {
    $c = $request.Clone()
    $c.Uri = "$base/$($conn.Project)/_apis/wit/workItems/$Id/comments?api-version=$($conn.ApiVersion)-preview.3"
    try {
        $comments = Invoke-RestMethod @c
        $lines = foreach ($cm in $comments.comments) { "- " + (ConvertFrom-AdoHtml $cm.text) }
        $commentsText = if ($lines) { $lines -join "`n" } else { "None" }
    }
    catch {
        $commentsText = "Could not fetch comments: $($_.Exception.Message)"
    }
}

# Web link to the work item, for the dashboard and PR text.
$webLink = Get-AdoProp (Get-AdoProp (Get-AdoProp $item "_links") "html") "href"
if (-not $webLink) {
    $webLink = if ($conn.Project) { "$base/$([System.Uri]::EscapeDataString($conn.Project))/_workitems/edit/$Id" } else { "$base/_workitems/edit/$Id" }
}

$folder = New-WorkFolder $itemTitle

$md = @"
# Work item ${Id}: $itemTitle

- Type: $type
- State: $state
- Area: $area
- Iteration: $iteration
- Tags: $tags
- ADO: $($conn.Name) ($($conn.Collection)$(if ($conn.Project) { "/" + $conn.Project }))
- Link: $webLink
- Fetched: $today

## Description

$description

## Acceptance criteria

$criteria

## Repro steps (bugs only)

$repro

## Related work items

$relatedText$parentsBlock

## Comments

$commentsText

## Extra context from the engineer

<anything else>
"@

Write-Utf8 (Join-Path $folder "workitem.md") $md
Write-Output "Fetched work item $Id ($type) from '$($conn.Name)': $itemTitle"
Write-Output (Resolve-Path $folder).Path
