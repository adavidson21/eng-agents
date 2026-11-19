<#
.SYNOPSIS
    Checks a story's plan against the breakdown it came from (Core 4.10.0). Prints why it drifted, or that it is clean.

.DESCRIPTION
    A story made by /backlog <scope> local from an approved breakdown has "- Breakdown: approved" in workitem.md.
    The engineer approved that breakdown, so its plan may be approved without them (/approve <id> spec auto) as long
    as it stays inside what the breakdown said. This script reads the story's tasks.md and plan.md and checks:

      cap        no task changes more than taskFileCap files (.work/factory.json, default 6; test files do not count)
      dependency no package manifest or lock file changes (a new dependency)
      migration  no migration, schema or .sql file changes
      security   no auth, login, token, permission, crypto or secret code changes
      areas      every changed file is under an area in "- Areas:" (when the story names areas), and every task's
                 repo is in "- Repos:" (when it names repos). Test files may be anywhere.

    Output: one "drift: <reason>" line per problem, then CLEAN (exit 0) or DRIFT (exit 1).
    A folder that is not a story from an approved breakdown prints NOT-A-STORY (exit 2). No files are changed.

.EXAMPLE
    .\Test-StoryDrift.ps1 -Folder .work\L14-invite-members
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Folder,

    # Default: .work/factory.json next to the item's folder, else 6.
    [int]$TaskFileCap = 0
)

$ErrorActionPreference = "Stop"

function Read-Text([string]$Path) {
    if (Test-Path -LiteralPath $Path) { return [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path) }
    return ""
}
function Get-Field([string]$Text, [string]$Name) {
    $m = [regex]::Match($Text, "(?m)^\s*-\s*${Name}:\s*(.+?)\s*$")
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ""
}
function Split-List([string]$Value) {
    return @(($Value -replace '`', '') -split '\s*,\s*' | ForEach-Object { $_.Trim().Trim('/').Replace('\', '/') } | Where-Object { $_ -and $_ -notmatch '^(none|-)$' })
}

if (-not (Test-Path -LiteralPath $Folder)) { throw "No folder $Folder." }
$wi = Read-Text (Join-Path $Folder "workitem.md")
if ($wi -notmatch '(?m)^\s*-\s*Breakdown:\s*approved\b') {
    Write-Output "NOT-A-STORY"
    exit 2
}

if ($TaskFileCap -le 0) {
    $TaskFileCap = 6
    $factory = Join-Path (Split-Path (Resolve-Path -LiteralPath $Folder).Path -Parent) "factory.json"
    if (Test-Path -LiteralPath $factory) {
        try {
            $f = Get-Content -LiteralPath $factory -Raw | ConvertFrom-Json
            if ($f.taskFileCap -is [int] -or $f.taskFileCap -is [long]) { if ($f.taskFileCap -ge 2 -and $f.taskFileCap -le 12) { $TaskFileCap = [int]$f.taskFileCap } }
        } catch { }
    }
}

$areas = Split-List (Get-Field $wi "Areas")
$repos = Split-List (Get-Field $wi "Repos")

$testRe = '(?i)(^|/)(tests?|specs?|__tests__|e2e)(/|$)|[._-](test|spec|tests)\.[a-z0-9]+$|Tests?\.[a-z]+$|/[^/]*Tests?/'
$depRe = '(?i)(^|/)(package(-lock)?\.json|yarn\.lock|pnpm-lock\.yaml|npm-shrinkwrap\.json|packages\.config|Directory\.Packages\.props|[^/]+\.csproj|[^/]+\.fsproj|requirements[^/]*\.txt|pyproject\.toml|Pipfile(\.lock)?|poetry\.lock|go\.(mod|sum)|Gemfile(\.lock)?|pom\.xml|build\.gradle(\.kts)?|Cargo\.(toml|lock)|composer\.(json|lock))$'
$migRe = '(?i)(^|/)migrations?(/|$)|migration|\.sql$|(^|/)schema\.prisma$|flyway|liquibase|alembic'
$secRe = '(?i)(auth|login|logon|password|token|jwt|oauth|saml|permission|rbac|crypto|encrypt|secret|credential|security|identity)'

# Every file the plan names: tasks.md's Files lists (per task, with its repo), and plan.md's "Changes by repo" tables.
$tasks = New-Object System.Collections.ArrayList
$cur = $null
foreach ($line in ((Read-Text (Join-Path $Folder "tasks.md")) -split "\r?\n")) {
    if ($line -match '^##\s+\[[ xX]\]\s+Task\s+(\d+)') { $cur = [ordered]@{ N = [int]$Matches[1]; Repo = ""; Files = (New-Object System.Collections.ArrayList); InFiles = $false }; [void]$tasks.Add($cur); continue }
    if (-not $cur) { continue }
    if ($line -match '^##\s') { $cur = $null; continue }
    if ($line -match '^\s*-\s*Repo:\s*`?([^`]+?)`?\s*$') { $cur.Repo = $Matches[1].Trim().Replace('\', '/'); $cur.InFiles = $false; continue }
    if ($line -match '^\s*-\s*Files:\s*$') { $cur.InFiles = $true; continue }
    if ($cur.InFiles -and $line -match '^\s{2,}-\s*`([^`]+)`') { [void]$cur.Files.Add($Matches[1].Trim().Replace('\', '/')); continue }
    if ($line -match '^\s*-\s*\S') { $cur.InFiles = $false }
}

$planFiles = New-Object System.Collections.ArrayList
$planRepo = ""
foreach ($line in ((Read-Text (Join-Path $Folder "plan.md")) -split "\r?\n")) {
    if ($line -match '^###\s+(.+?)\s*$') { $planRepo = $Matches[1].Trim().Trim('`').Replace('\', '/'); continue }
    if ($line -match '^\|\s*`([^`]+)`\s*\|') { [void]$planFiles.Add([pscustomobject]@{ Repo = $planRepo; File = $Matches[1].Trim().Replace('\', '/') }) }
}

if ($tasks.Count -eq 0 -and $planFiles.Count -eq 0) {
    Write-Output "drift: tasks.md and plan.md list no files, so the plan cannot be checked against the breakdown"
    Write-Output "DRIFT"
    exit 1
}

$problems = New-Object System.Collections.ArrayList
function Add-Problem([string]$Text) { if (-not $problems.Contains($Text)) { [void]$problems.Add($Text) } }

$all = New-Object System.Collections.ArrayList
foreach ($t in $tasks) {
    $nonTest = @($t.Files | Where-Object { $_ -notmatch $testRe })
    if ($nonTest.Count -gt $TaskFileCap) { Add-Problem "Task $($t.N) changes $($nonTest.Count) files (the cap is $TaskFileCap; test files do not count)" }
    if ($repos.Count -and $t.Repo -and -not ($repos | Where-Object { $_ -ieq $t.Repo -or $t.Repo -ilike "*/$_" -or $_ -ilike "*/$($t.Repo)" })) { Add-Problem "Task $($t.N) is in repo $($t.Repo), which the breakdown does not name" }
    foreach ($f in $t.Files) { [void]$all.Add([pscustomobject]@{ Repo = $t.Repo; File = $f }) }
}
foreach ($p in $planFiles) { [void]$all.Add($p) }

foreach ($x in $all) {
    $f = $x.File
    $full = if ($x.Repo -and -not $f.StartsWith("$($x.Repo)/", [StringComparison]::OrdinalIgnoreCase)) { "$($x.Repo)/$f" } else { $f }
    if ($f -match $depRe) { Add-Problem "a dependency may change: $full" }
    if ($f -match $migRe) { Add-Problem "a migration or schema change: $full" }
    if ($f -match $secRe -and $f -notmatch $testRe) { Add-Problem "auth or security code: $full" }
    if ($areas.Count -and $f -notmatch $testRe) {
        $inside = $false
        foreach ($a in $areas) {
            if ($full.StartsWith("$a/", [StringComparison]::OrdinalIgnoreCase) -or $full -ieq $a -or
                $f.StartsWith("$a/", [StringComparison]::OrdinalIgnoreCase) -or $f -ieq $a) { $inside = $true; break }
        }
        if (-not $inside) { Add-Problem "outside the breakdown's areas: $full" }
    }
}

foreach ($p in $problems) { Write-Output "drift: $p" }
if ($problems.Count) { Write-Output "DRIFT"; exit 1 }
Write-Output "CLEAN"
exit 0
