<#
.SYNOPSIS
    Shared helpers for the GitHub scripts: the token, REST and GraphQL calls, and reading an issue body.
    Dot-source it: . (Join-Path $PSScriptRoot "GitHubCommon.ps1")

.DESCRIPTION
    Read-only. The token comes from the first environment variable that is set of GITHUB_PAT (the name
    Workshop's GitHub connector uses), GH_TOKEN and GITHUB_TOKEN, or else from "gh auth token" when the
    GitHub CLI is installed and signed in. It is sent only in the Authorization header and never written to disk.

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

function Get-GitHubToken {
    foreach ($name in @("GITHUB_PAT", "GH_TOKEN", "GITHUB_TOKEN")) {
        $v = [Environment]::GetEnvironmentVariable($name)
        if ($v -and $v.Trim()) { return $v.Trim() }
    }
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        $ErrorActionPreference = "Continue"
        $t = (& gh auth token 2>$null | Select-Object -First 1)
        if ($LASTEXITCODE -eq 0 -and $t -and "$t".Trim()) { return "$t".Trim() }
    }
    throw "NOTOKEN: no GitHub token. Set GITHUB_PAT (workshop pat GITHUB_PAT), or sign in with: gh auth login"
}

function New-GitHubHeaders {
    $token = Get-GitHubToken
    return @{
        Authorization          = "Bearer $token"
        Accept                 = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
        "User-Agent"           = "eng-agents"
    }
}

function Invoke-GitHubRest {
    param([hashtable]$Headers, [string]$Path, [string]$What)
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
