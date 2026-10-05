<#
.SYNOPSIS
    Fetches an Azure DevOps work item and creates its pipeline folder under .work.

.DESCRIPTION
    Online mode (default): reads the work item from ADO Server over REST and writes
    <WorkRoot>\<Id>-<short-name>\workitem.md.

    Offline mode (-Title): skips ADO and creates the same folder with an empty
    workitem.md for the engineer to paste into.

    The LAST line of output is always the folder path, so the calling agent can use it.

    Settings come from config.json (see config.example.json). The PAT comes from the
    ADO_PAT environment variable and is never written to disk.

.EXAMPLE
    .\Get-WorkItem.ps1 -Id 12345 -WorkRoot .work

.EXAMPLE
    .\Get-WorkItem.ps1 -Id 12345 -WorkRoot .work -Title "Export job fails on retry"
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
    [switch]$IncludeComments
)

$ErrorActionPreference = "Stop"

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

function ConvertFrom-AdoHtml {
    param([string]$Html)
    if (-not $Html) { return "" }
    $t = $Html
    $t = $t -replace "(?i)<br\s*/?>", "`n"
    $t = $t -replace "(?i)</(p|div|h[1-6]|tr)>", "`n"
    $t = $t -replace "(?i)<li[^>]*>", "`n- "
    $t = $t -replace "(?i)</(td|th)>", " | "
    $t = $t -replace "<[^>]+>", ""
    $t = [System.Net.WebUtility]::HtmlDecode($t)
    $t = $t -replace "[ \t]+\n", "`n"
    $t = $t -replace "\n{3,}", "`n`n"
    return $t.Trim()
}

function Get-Field {
    param($Fields, [string]$Name)
    $p = $Fields.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

function Write-Utf8 {
    param([string]$Path, [string]$Content)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
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
if (-not (Test-Path $ConfigPath)) {
    throw "Config not found at $ConfigPath. Copy config.example.json there and fill it in, or use -Title for offline mode."
}
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

foreach ($key in @("serverUrl", "collection", "apiVersion")) {
    if (-not $config.$key) { throw "config.json is missing '$key'." }
}
if ($config.serverUrl -match "example\.local") {
    throw "config.json still has the example serverUrl. Fill in your real ADO Server URL."
}

$auth = if ($config.auth) { $config.auth } else { "pat" }
$request = @{ Method = "Get"; ContentType = "application/json" }

if ($auth -eq "windows") {
    $request.UseDefaultCredentials = $true
}
else {
    if (-not $env:ADO_PAT) { throw "ADO_PAT environment variable is not set. Set it, or use -Title for offline mode." }
    $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":" + $env:ADO_PAT))
    $request.Headers = @{ Authorization = "Basic $basic" }
}

# Windows PowerShell 5.1 may default to old TLS versions.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

$base = "$($config.serverUrl.TrimEnd('/'))/$($config.collection)"
$request.Uri = "$base/_apis/wit/workitems/$($Id)?`$expand=relations&api-version=$($config.apiVersion)"

try {
    $item = Invoke-RestMethod @request
}
catch {
    throw "ADO request failed for work item $Id. $($_.Exception.Message)"
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

$commentsText = "Not fetched (use -IncludeComments)"
if ($IncludeComments) {
    $c = $request.Clone()
    $c.Uri = "$base/$($config.project)/_apis/wit/workItems/$Id/comments?api-version=$($config.apiVersion)-preview.3"
    try {
        $comments = Invoke-RestMethod @c
        $lines = foreach ($cm in $comments.comments) { "- " + (ConvertFrom-AdoHtml $cm.text) }
        $commentsText = if ($lines) { $lines -join "`n" } else { "None" }
    }
    catch {
        $commentsText = "Could not fetch comments: $($_.Exception.Message)"
    }
}

$folder = New-WorkFolder $itemTitle

$md = @"
# Work item ${Id}: $itemTitle

- Type: $type
- State: $state
- Area: $area
- Iteration: $iteration
- Tags: $tags
- Fetched: $today

## Description

$description

## Acceptance criteria

$criteria

## Repro steps (bugs only)

$repro

## Related work items

$relatedText

## Comments

$commentsText

## Extra context from the engineer

<anything else>
"@

Write-Utf8 (Join-Path $folder "workitem.md") $md
Write-Output "Fetched work item $Id ($type): $itemTitle"
Write-Output (Resolve-Path $folder).Path
