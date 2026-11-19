<#
.SYNOPSIS
  Offline checks for the GitHub scripts: ids, remotes, types, body sections, Get-GitHubIssue.ps1 writing a
  local work item from a saved issue, and reads through Workshop when there is no token here (Workshop is faked:
  no network, no token).
  Run: pwsh -NoProfile -File core/scripts/github/Test-GitHub.ps1   (also works in Windows PowerShell 5.1)
#>
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "GitHubCommon.ps1")

$failed = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = "") {
    if ($Ok) { Write-Output "ok   $Name" } else { Write-Output "FAIL $Name $Detail"; $script:failed++ }
}

# ------------------------------------------------------------------ helpers
$r = ConvertFrom-GitHubIssueId "acme/web#12"
Check "issue id owner/repo#12" ($r.Repo -eq "acme/web" -and $r.Number -eq 12)
Check "a bare number is not a full id" ($null -eq (ConvertFrom-GitHubIssueId "12"))
Check "https remote" ((ConvertFrom-GitHubRemote "https://github.com/acme/web.git") -eq "acme/web")
Check "ssh remote" ((ConvertFrom-GitHubRemote "git@github.com:acme/web.git") -eq "acme/web")
Check "an ADO remote is not GitHub-shaped" ($null -eq (ConvertFrom-GitHubRemote "https://ado.example.com/tfs/Main/Shop/_git/orders"))
Check "type from labels" ((Get-GitHubType @("P1", "Bug")) -eq "Bug")
Check "story label" ((Get-GitHubType @("story")) -eq "User Story")
Check "no type label is an Issue" ((Get-GitHubType @("docs")) -eq "Issue")
$b = Split-GitHubBody "Intro`n`n## Repro steps`n1. a`n`n### Acceptance Criteria`n- b`n`n## Notes`nmore"
Check "repro section" ($b.ReproSteps -eq "1. a") $b.ReproSteps
Check "acceptance section" ($b.AcceptanceCriteria -eq "- b") $b.AcceptanceCriteria
Check "other headings stay in the description" ($b.Description -eq "Intro`n`n## Notes`nmore") $b.Description
Check "GraphQL URL for github.com" ((Get-GitHubGraphQlUrl) -eq "https://api.github.com/graphql")

# ------------------------------------------------------------------ Get-GitHubIssue.ps1 offline
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("gh-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $work = Join-Path $tmp ".work"
    $json = Join-Path $tmp "issue.json"
    $issue = @{
        number = 12; title = "Fix login timeout"; state = "open"; html_url = "https://github.com/acme/web/issues/12"
        body = "The login page times out.`n`n## Repro steps`n1. Open login`n`n## Acceptance criteria`n- No timeout"
        labels = @(@{ name = "bug" }, @{ name = "P2" }); milestone = @{ title = "v2.1" }
        parent = @{ number = 3; title = "Sign-in overhaul"; url = "https://github.com/acme/web/issues/3"; state = "OPEN"; repository = @{ nameWithOwner = "acme/web" }; labels = @{ nodes = @(@{ name = "feature" }) } }
        comments_list = @(@{ body = "Seen on staging"; user = @{ login = "sam" } })
    }
    Write-GitHubUtf8 $json ($issue | ConvertTo-Json -Depth 10)
    $out = & (Join-Path $PSScriptRoot "Get-GitHubIssue.ps1") -Id "acme/web#12" -WorkRoot $work -IssueJson $json
    $folder = @($out)[-1]
    Check "last line is the folder" (Test-Path (Join-Path $folder "workitem.md")) $folder
    Check "it is a local work item" ((Split-Path -Leaf $folder) -like "L1-*") (Split-Path -Leaf $folder)
    # Windows checks out the script with CRLF, so lines may end in \r: the line checks allow it.
    $md = [IO.File]::ReadAllText((Join-Path $folder "workitem.md"))
    Check "title line" ($md -match '(?m)^# Work item L1: Fix login timeout\s*$')
    Check "GitHub source line" ($md -match '(?m)^- GitHub: acme/web#12\s*$')
    Check "type from the bug label" ($md -match '(?m)^- Type: Bug\s*$')
    Check "link" ($md -match [regex]::Escape("- Link: https://github.com/acme/web/issues/12"))
    Check "description" ($md -match "(?s)## Description\s+The login page times out\.\s+## Acceptance criteria\s+- No timeout")
    Check "repro" ($md -match "(?s)## Repro steps \(bugs only\)\s+1\. Open login")
    Check "parent feature then milestone epic" ($md -match "(?s)## Parents\s+Nearest first\.\s+- Feature: acme/web#3 Sign-in overhaul\s+- Epic \(milestone\): v2\.1")
    Check "comments" ($md -match "- sam: Seen on staging")
    $again = & (Join-Path $PSScriptRoot "Get-GitHubIssue.ps1") -Id "acme/web#12" -WorkRoot $work -IssueJson $json
    Check "a second fetch says ALREADY and names the folder" ((@($again)[0] -like "ALREADY:*") -and (@($again)[-1] -eq $folder)) ($again -join " | ")
    $bad = $null
    try { & (Join-Path $PSScriptRoot "Get-GitHubIssue.ps1") -Id "12" -WorkRoot $work -IssueJson $json | Out-Null } catch { $bad = $_.Exception.Message }
    Check "a bare number with no repo is BADID" ("$bad" -like "BADID:*") "$bad"
}
finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }

# ------------------------------------------------------------------ through Workshop (no token here)
# An error the way Invoke-RestMethod throws it, with Workshop's JSON body.
function Fail-With([int]$Status, [string]$Code, [string]$Message) {
    $ex = New-Object System.Exception "HTTP $Status"
    $ex | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{ StatusCode = $Status }) -Force
    $err = New-Object System.Management.Automation.ErrorRecord $ex, "fake", ([System.Management.Automation.ErrorCategory]::InvalidOperation), $null
    $err.ErrorDetails = New-Object System.Management.Automation.ErrorDetails ((@{ error = $Message; code = $Code } | ConvertTo-Json -Compress))
    throw $err
}
# The fake: Invoke-RestMethod is a function here, so GitHubCommon's calls land in it. Globals, as in Test-WorkshopTool.
$global:GhCalls = New-Object System.Collections.ArrayList
$global:GhReply = $null
function Invoke-RestMethod {
    param($Method, $Uri, $Headers, $ContentType, $Body, $TimeoutSec)
    $text = if ($Body -is [byte[]]) { [System.Text.Encoding]::UTF8.GetString($Body) } else { $Body }
    [void]$global:GhCalls.Add([pscustomobject]@{ Method = "$Method"; Uri = "$Uri"; Headers = $Headers; Body = $text })
    if ("$Uri" -match '/api/tools$') { return [pscustomobject]@{ tools = @([pscustomobject]@{ connector = "github"; action = "api.get" }) } }
    if ($global:GhReply -is [scriptblock]) { return & $global:GhReply }
    return $global:GhReply
}
$saved = @{}
foreach ($n in @("GITHUB_PAT", "GH_TOKEN", "GITHUB_TOKEN", "WORKSHOP_HOME")) { $saved[$n] = [Environment]::GetEnvironmentVariable($n); [Environment]::SetEnvironmentVariable($n, $null) }
$ws = Join-Path ([IO.Path]::GetTempPath()) ("ghws-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $ws | Out-Null
try {
    $env:WORKSHOP_HOME = $ws
    [IO.File]::WriteAllText((Join-Path $ws "agent-token"), ("cd" * 32) + "`n")
    [IO.File]::WriteAllText((Join-Path $ws "config.json"), '{"port": 4391}')
    $h = New-GitHubHeaders
    Check "no token here and Workshop offers GitHub: calls go through Workshop" ($h.ContainsKey("Workshop") -and -not $h.ContainsKey("Authorization"))

    $global:GhCalls.Clear()
    $global:GhReply = [pscustomobject]@{ result = [pscustomobject]@{ number = 12; title = "Fix login timeout" } }
    $issue = Invoke-GitHubRest $h "/repos/acme/web/issues/12" "issue acme/web#12"
    $c = $global:GhCalls[0]
    Check "REST read is Workshop's api.get" ($c.Uri -eq "http://127.0.0.1:4391/api/tools/github/api.get" -and $c.Method -eq "Post") $c.Uri
    Check "with the path as its argument" ((($c.Body | ConvertFrom-Json).args.path) -eq "/repos/acme/web/issues/12") $c.Body
    Check "with the agent token, and no GitHub token" ($c.Headers["X-Workshop-Agent-Token"] -eq ("cd" * 32) -and -not $c.Headers.ContainsKey("Authorization"))
    Check "returns what GitHub returned" ($issue.title -eq "Fix login timeout")

    $global:GhCalls.Clear()
    $global:GhReply = [pscustomobject]@{ result = [pscustomobject]@{ repository = [pscustomobject]@{ issue = [pscustomobject]@{ id = "I_1" } } } }
    $g = Invoke-GitHubGraphQl $h "query(`$n:Int!){ repository(owner:`"acme`",name:`"web`"){ issue(number:`$n){ id } } }" @{ n = 12 }
    $c = $global:GhCalls[0]
    Check "GraphQL is Workshop's graphql.query, with variables" ($c.Uri -like "*/api/tools/github/graphql.query" -and (($c.Body | ConvertFrom-Json).args.variables.n) -eq 12) $c.Body
    Check "returns the data" ($g.repository.issue.id -eq "I_1")

    $global:GhReply = { Fail-With 404 "not_found" "GitHub could not find /repos/acme/web/issues/99." }
    $err = $null; try { Invoke-GitHubRest $h "/repos/acme/web/issues/99" "issue acme/web#99" | Out-Null } catch { $err = $_.Exception.Message }
    Check "a 404 from GitHub is NOTFOUND" ("$err" -like "NOTFOUND: issue acme/web#99*") "$err"
    $global:GhReply = { Fail-With 503 "unavailable" "No GitHub token: the secret github-pat is not saved." }
    $err = $null; try { Invoke-GitHubRest $h "/repos/acme/web/issues/1" "issue acme/web#1" | Out-Null } catch { $err = $_.Exception.Message }
    Check "Workshop with no token saved is NOTOKEN" ("$err" -like "NOTOKEN: No GitHub token*") "$err"

    $env:GITHUB_PAT = "ghp_test"
    $h = New-GitHubHeaders
    Check "a token in the environment still wins" ($h["Authorization"] -eq "Bearer ghp_test" -and -not $h.ContainsKey("Workshop"))
    $env:GITHUB_PAT = $null
    Remove-Item (Join-Path $ws "agent-token")
    $global:GhCalls.Clear()
    $viaWs = $false; try { $viaWs = (New-GitHubHeaders).ContainsKey("Workshop") } catch { }
    Check "no Workshop token: Workshop is not asked" (-not $viaWs -and $global:GhCalls.Count -eq 0)
}
finally {
    foreach ($n in $saved.Keys) { [Environment]::SetEnvironmentVariable($n, $saved[$n]) }
    Remove-Variable -Name GhCalls, GhReply -Scope Global -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $ws -ErrorAction SilentlyContinue
}

if ($failed) { Write-Output "$failed failed"; exit 1 }
Write-Output "All GitHub checks passed"
# The ALREADY check above leaves LASTEXITCODE at 1 on purpose; this run passed.
exit 0
