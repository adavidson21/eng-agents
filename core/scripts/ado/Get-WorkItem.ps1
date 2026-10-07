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

    # A connection name from config.json, or a repo folder whose path or git remote
    # identifies the connection.
    [string]$From,

    # Print which connection would be used and why, then exit. Calls nothing.
    [switch]$ShowConnection
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

function Get-Prop {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

function ConvertTo-PathKey {
    # Lowercase, forward slashes, no trailing slash. "~" expands to the home folder.
    param([string]$Path)
    $home2 = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    if ($Path -eq "~") { $Path = $home2 }
    elseif ($Path.StartsWith("~/") -or $Path.StartsWith("~\")) { $Path = Join-Path $home2 $Path.Substring(2) }
    return $Path.Replace("\", "/").TrimEnd("/").ToLowerInvariant()
}

function ConvertTo-UrlKey {
    # host + path, lowercase, without scheme, user, or port. Works for https and ssh remotes.
    param([string]$Url)
    $u = $Url.Trim().ToLowerInvariant()
    $u = $u -replace "^[a-z+]+://", ""
    $u = $u -replace "^[^@/]+@", ""
    $u = $u -replace "^([^/:]+):\d+", '$1'
    $u = $u -replace "^([^/:]+):(?!/)", '$1/'
    return $u.TrimEnd("/")
}

# Build the connection list. A flat config (serverUrl at the top) is one connection named "default".
$connections = [ordered]@{}
$topApi = Get-Prop $config "apiVersion"
$topAuth = Get-Prop $config "auth"
$topPatEnv = Get-Prop $config "patEnv"
$connSource = Get-Prop $config "connections"
if ($connSource) {
    foreach ($p in $connSource.PSObject.Properties) { $connections[$p.Name] = $p.Value }
}
elseif (Get-Prop $config "serverUrl") {
    $connections["default"] = $config
}
if ($connections.Count -eq 0) { throw "config.json has no 'connections' (or 'serverUrl'). See config.example.json." }

$names = @($connections.Keys)
$namesText = $names -join ", "

function Get-Connection {
    param([string]$Name)
    $c = $connections[$Name]
    $conn = [pscustomobject]@{
        Name       = $Name
        ServerUrl  = (Get-Prop $c "serverUrl")
        Collection = (Get-Prop $c "collection")
        Project    = (Get-Prop $c "project")
        ApiVersion = $(if (Get-Prop $c "apiVersion") { Get-Prop $c "apiVersion" } elseif ($topApi) { $topApi } else { "6.0" })
        Auth       = $(if (Get-Prop $c "auth") { Get-Prop $c "auth" } elseif ($topAuth) { $topAuth } else { "pat" })
        PatEnv     = $(if (Get-Prop $c "patEnv") { Get-Prop $c "patEnv" } elseif ($topPatEnv) { $topPatEnv } else { "ADO_PAT" })
        Reason     = ""
    }
    foreach ($key in @("ServerUrl", "Collection")) {
        if (-not $conn.$key) { throw "Connection '$Name' in config.json is missing '$($key.Substring(0,1).ToLowerInvariant() + $key.Substring(1))'." }
    }
    if ($conn.ServerUrl -match "example\.local") {
        throw "Connection '$Name' still has the example serverUrl. Fill in your real ADO Server URL in $ConfigPath."
    }
    return $conn
}

function Find-PathMapping {
    # Longest matching pattern wins. "*" matches any characters, including slashes.
    param([string]$Path)
    $map = Get-Prop $config "paths"
    if (-not $map) { return $null }
    $key = ConvertTo-PathKey $Path
    $best = $null
    $bestLen = -1
    foreach ($p in $map.PSObject.Properties) {
        $pattern = ConvertTo-PathKey $p.Name
        if (($key -like $pattern) -or ("$key/" -like $pattern) -or ($key -like "$pattern/*")) {
            if ($pattern.Length -gt $bestLen) { $best = $p; $bestLen = $pattern.Length }
        }
    }
    if ($best) {
        if (-not $connections.Contains([string]$best.Value)) { throw "config.json 'paths' maps '$($best.Name)' to '$($best.Value)', which is not a connection. Connections: $namesText" }
        return [pscustomobject]@{ Name = [string]$best.Value; Pattern = $best.Name }
    }
    return $null
}

function Find-RemoteMapping {
    # Match the repo's origin URL against each connection's serverUrl + collection.
    param([string]$RepoPath)
    $url = $null
    try { $url = (& git -C $RepoPath remote get-url origin 2>$null) } catch { }
    if (-not $url) { return $null }
    $urlKey = ConvertTo-UrlKey ([string]$url)
    foreach ($n in $names) {
        $c = $connections[$n]
        $server = Get-Prop $c "serverUrl"
        $coll = Get-Prop $c "collection"
        if (-not $server -or -not $coll) { continue }
        $prefix = (ConvertTo-UrlKey $server) + "/" + $coll.ToLowerInvariant() + "/"
        if ($urlKey.StartsWith($prefix)) {
            $project = $null
            if (([string]$url) -match ("(?i)/" + [regex]::Escape($coll) + "/([^/]+)/_git/")) { $project = [System.Uri]::UnescapeDataString($Matches[1]) }
            return [pscustomobject]@{ Name = $n; Url = [string]$url; Project = $project }
        }
    }
    return [pscustomobject]@{ Name = $null; Url = [string]$url; Project = $null }
}

# Pick the connection.
$conn = $null
$repoPath = $null
$remoteNote = $null
if ($From) {
    if ($connections.Contains($From)) {
        $conn = Get-Connection $From
        $conn.Reason = "named with -From"
    }
    elseif (Test-Path $From -PathType Container) {
        $repoPath = (Resolve-Path $From).Path
    }
    else {
        throw "UNKNOWN: -From '$From' is not a connection name or a folder. Connections: $namesText"
    }
}
if (-not $conn -and $repoPath) {
    $m = Find-PathMapping $repoPath
    if ($m) { $conn = Get-Connection $m.Name; $conn.Reason = "repo path matches '$($m.Pattern)'" }
    else {
        $r = Find-RemoteMapping $repoPath
        if ($r -and $r.Name) {
            $conn = Get-Connection $r.Name
            $conn.Reason = "repo remote $($r.Url)"
            if ($r.Project) { $conn.Project = $r.Project }
        }
        elseif ($r) { $remoteNote = "The remote $($r.Url) matches no connection's serverUrl + collection." }
    }
}
if (-not $conn) {
    $m = Find-PathMapping (Get-Location).Path
    if ($m) { $conn = Get-Connection $m.Name; $conn.Reason = "current folder matches '$($m.Pattern)'" }
}
if (-not $conn) {
    $def = Get-Prop $config "default"
    if ($def) {
        if (-not $connections.Contains([string]$def)) { throw "config.json 'default' is '$def', which is not a connection. Connections: $namesText" }
        $conn = Get-Connection ([string]$def); $conn.Reason = "default connection"
    }
    elseif ($names.Count -eq 1) {
        $conn = Get-Connection $names[0]; $conn.Reason = "only connection"
    }
}
if (-not $conn) {
    $msg = "AMBIGUOUS: could not tell which ADO connection to use. Rerun with -From <connection name or repo folder>. Connections: $namesText"
    if ($remoteNote) { $msg += " ($remoteNote)" }
    throw $msg
}

$base = "$($conn.ServerUrl.TrimEnd('/'))/$($conn.Collection)"

if ($ShowConnection) {
    Write-Output "Connection : $($conn.Name) ($($conn.Reason))"
    Write-Output "Base URL   : $base"
    Write-Output "Project    : $(if ($conn.Project) { $conn.Project } else { '(not set; only needed for -IncludeComments)' })"
    Write-Output "API version: $($conn.ApiVersion)"
    if ($conn.Auth -eq "windows") { Write-Output "Auth       : windows (your Windows login)" }
    else {
        $isSet = if ([Environment]::GetEnvironmentVariable($conn.PatEnv)) { "set" } else { "NOT SET" }
        Write-Output "Auth       : pat from $($conn.PatEnv) ($isSet)"
    }
    exit 0
}

$request = @{ Method = "Get"; ContentType = "application/json" }

if ($conn.Auth -eq "windows") {
    $request.UseDefaultCredentials = $true
}
else {
    $pat = [Environment]::GetEnvironmentVariable($conn.PatEnv)
    if (-not $pat) { throw "$($conn.PatEnv) environment variable is not set (connection '$($conn.Name)'). Set it, or use -Title for offline mode." }
    $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":" + $pat))
    $request.Headers = @{ Authorization = "Basic $basic" }
}

# Windows PowerShell 5.1 may default to old TLS versions.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

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

$folder = New-WorkFolder $itemTitle

$md = @"
# Work item ${Id}: $itemTitle

- Type: $type
- State: $state
- Area: $area
- Iteration: $iteration
- Tags: $tags
- ADO: $($conn.Name) ($($conn.Collection)$(if ($conn.Project) { "/" + $conn.Project }))
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
Write-Output "Fetched work item $Id ($type) from '$($conn.Name)': $itemTitle"
Write-Output (Resolve-Path $folder).Path
