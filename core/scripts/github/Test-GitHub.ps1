<#
.SYNOPSIS
  Offline checks for the GitHub scripts: ids, remotes, types, body sections, and Get-GitHubIssue.ps1 writing a
  local work item from a saved issue (no network, no token).
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
    $md = [IO.File]::ReadAllText((Join-Path $folder "workitem.md"))
    Check "title line" ($md -match '(?m)^# Work item L1: Fix login timeout$')
    Check "GitHub source line" ($md -match '(?m)^- GitHub: acme/web#12$')
    Check "type from the bug label" ($md -match '(?m)^- Type: Bug$')
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

if ($failed) { Write-Output "$failed failed"; exit 1 }
Write-Output "All GitHub checks passed"
# The ALREADY check above leaves LASTEXITCODE at 1 on purpose; this run passed.
exit 0
