<#
.SYNOPSIS
    Shared helpers for the GitHub scripts: the token, REST and GraphQL calls, and reading an issue body.
    Dot-source it: . (Join-Path $PSScriptRoot "GitHubCommon.ps1")

.DESCRIPTION
    Read-only. Where the token comes from, first match wins:
      1. An environment variable: GITHUB_PAT (the name Workshop's GitHub connector uses), GH_TOKEN, GITHUB_TOKEN.
      2. Workshop: when Workshop is running here and its GitHub connector offers api.get, the calls go through
         Workshop's tools for agents (api.get, graphql.query) and the token stays in Workshop's secret store (the
         Mac Keychain, Windows Credential Manager): this script never sees it.
      3. "gh auth token", when the GitHub CLI is installed and signed in.
    A token is sent only in the Authorization header and never written to disk.

    The API URL is https://api.github.com unless GITHUB_API_URL is set (GitHub Enterprise Server:
    https://<server>/api/v3).
#>

function Get-GitHubApiUrl {
    $u = "$env:GITHUB_API_URL".Trim().TrimEnd("/")
    if ($u) { return $u }
    return "https://api.github.com"
}

function Get-GitHubGraphQlUrl {
    $api = Get-GitHubApiUrl
    if ($api -eq "https://api.github.com") { return "https://api.github.com/graphql" }
    if ($api -match '/api/v3$') { return ($api -replace '/api/v3$', '/api/graphql') }
    return "$api/graphql"
}

. (Join-Path $PSScriptRoot "../workshop/WorkshopCommon.ps1")

function Get-NoGitHubTokenText {
    return "NOTOKEN: no GitHub token. Save one in Workshop (workshop secret set github-pat --expires <date>, then Settings, GitHub: Token secret github-pat), set GITHUB_PAT, or sign in with: gh auth login"
}

function Get-GitHubEnvToken {
    foreach ($name in @("GITHUB_PAT", "GH_TOKEN", "GITHUB_TOKEN")) {
        $v = [Environment]::GetEnvironmentVariable($name)
        if ($v -and $v.Trim()) { return $v.Trim() }
    }
    return $null
}

function Get-GitHubCliToken {
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        $ErrorActionPreference = "Continue"
        $t = (& gh auth token 2>$null | Select-Object -First 1)
        if ($LASTEXITCODE -eq 0 -and $t -and "$t".Trim()) { return "$t".Trim() }
    }
    return $null
}

# A token from the environment or the GitHub CLI. Not Workshop's: that one never leaves Workshop.
function Get-GitHubToken {
    $t = Get-GitHubEnvToken
    if (-not $t) { $t = Get-GitHubCliToken }
    if ($t) { return $t }
    throw (Get-NoGitHubTokenText)
}

function New-GitHubTokenHeaders([string]$Token) {
    return @{
        Authorization          = "Bearer $Token"
        Accept                 = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
        "User-Agent"           = "eng-agents"
    }
}

# What Invoke-GitHubRest and Invoke-GitHubGraphQl send with: token headers, or @{ Workshop = <agent> } when the calls
# go through Workshop (the order is in the description above).
function New-GitHubHeaders {
    $t = Get-GitHubEnvToken
    if ($t) { return (New-GitHubTokenHeaders $t) }
    $agent = Get-WorkshopAgent
    if (Test-WorkshopOffers $agent "github" "api.get") { return @{ Workshop = $agent } }
    $t = Get-GitHubCliToken
    if ($t) { return (New-GitHubTokenHeaders $t) }
    throw (Get-NoGitHubTokenText)
}

# One read through Workshop's GitHub connector, with the same errors as a direct call.
function Invoke-GitHubViaWorkshop {
    param($Agent, [string]$Action, [hashtable]$ToolArgs, [string]$What)
    try { return (Invoke-WorkshopApi $Agent "POST" "/github/$Action" @{ args = $ToolArgs }).result }
    catch {
        $e = Read-WorkshopError $_
        $msg = if ($e.Message) { $e.Message } else { "HTTP $($e.Status)." }
        if (-not $e.Status) { throw "GitHub request failed for ${What}: Workshop stopped answering on port $($Agent.Port)." }
        if ($e.Status -eq 404 -and $msg -notmatch '^There is no ') { throw "NOTFOUND: $What was not found on GitHub, or the token cannot see it." }
        if ($msg -match '(?i)token') { throw "NOTOKEN: $msg" }
        throw "GitHub request failed for ${What}: $msg"
    }
}

function Invoke-GitHubRest {
    param([hashtable]$Headers, [string]$Path, [string]$What)
    if ($Headers.ContainsKey("Workshop")) { return Invoke-GitHubViaWorkshop $Headers["Workshop"] "api.get" @{ path = $Path } $What }
    $uri = "$(Get-GitHubApiUrl)$Path"
    try { return Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers }
    catch {
        $code = $null
        try { $code = [int]$_.Exception.Response.StatusCode } catch { }
        if ($code -eq 404) { throw "NOTFOUND: $What was not found on GitHub, or the token cannot see it." }
        if ($code -eq 401) { throw "NOTOKEN: GitHub rejected the token (HTTP 401). Make a new one." }
        throw "GitHub request failed for ${What}: $($_.Exception.Message)"
    }
}

function Invoke-GitHubGraphQl {
    param([hashtable]$Headers, [string]$Query, [hashtable]$Variables)
    if ($Headers.ContainsKey("Workshop")) { return Invoke-GitHubViaWorkshop $Headers["Workshop"] "graphql.query" @{ query = $Query; variables = $Variables } "a GraphQL query" }
    $body = @{ query = $Query; variables = $Variables } | ConvertTo-Json -Depth 10 -Compress
    $r = Invoke-RestMethod -Method Post -Uri (Get-GitHubGraphQlUrl) -Headers $Headers -Body $body -ContentType "application/json"
    if ($r.errors) { throw "GitHub GraphQL: $($r.errors[0].message)" }
    return $r.data
}

# "owner/repo#12" -> @{ Repo; Number }, or $null.
function ConvertFrom-GitHubIssueId {
    param([string]$Id)
    $s = "$Id".Trim()
    if ($s -match '^([A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100})#(\d{1,9})$') {
        return @{ Repo = $Matches[1]; Number = [int]$Matches[2] }
    }
    return $null
}

# owner/repo from a git remote URL (https or ssh), or $null.
function ConvertFrom-GitHubRemote {
    param([string]$Url)
    $u = "$Url".Trim()
    if ($u -match '^(?:https?://[^/]+/|git@[^:]+:|ssh://git@[^/]+/)([A-Za-z0-9][A-Za-z0-9-]{0,38})/([A-Za-z0-9._-]+?)(?:\.git)?/?$') {
        return "$($Matches[1])/$($Matches[2])"
    }
    return $null
}

# The type from labels: epic, feature, story (or user story), bug, task. None of them: Issue.
function Get-GitHubType {
    param([string[]]$Labels)
    $map = @{ "epic" = "Epic"; "feature" = "Feature"; "story" = "User Story"; "user story" = "User Story"; "bug" = "Bug"; "task" = "Task" }
    foreach ($l in @($Labels)) {
        $k = "$l".Trim().ToLowerInvariant()
        if ($map.ContainsKey($k)) { return $map[$k] }
    }
    return "Issue"
}

# Splits a Markdown body into Description, AcceptanceCriteria and ReproSteps, from "## Acceptance criteria" and
# "## Repro steps" (or "Steps to reproduce") headings, ## or ###. Everything else is the description.
function Split-GitHubBody {
    param([string]$Body)
    $parts = @{ Description = New-Object System.Collections.ArrayList; AcceptanceCriteria = New-Object System.Collections.ArrayList; ReproSteps = New-Object System.Collections.ArrayList }
    $key = "Description"
    foreach ($line in ("$Body" -replace "`r`n?", "`n") -split "`n") {
        if ($line -match '^#{2,3}\s+(.+?)\s*#*\s*$') {
            $h = $Matches[1].Trim()
            if ($h -match '^(?i)acceptance criteria$') { $key = "AcceptanceCriteria"; continue }
            if ($h -match '^(?i)(repro steps|steps to reproduce|reproduction steps)$') { $key = "ReproSteps"; continue }
            $key = "Description"
        }
        [void]$parts[$key].Add($line)
    }
    return @{
        Description        = (($parts.Description) -join "`n").Trim()
        AcceptanceCriteria = (($parts.AcceptanceCriteria) -join "`n").Trim()
        ReproSteps         = (($parts.ReproSteps) -join "`n").Trim()
    }
}

function Write-GitHubUtf8 {
    param([string]$Path, [string]$Content)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}
