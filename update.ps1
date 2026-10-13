<#
.SYNOPSIS
    Updates eng-agents: pulls the repo, warns about Core changes to files you override,
    then reinstalls everything or only the dashboard.

.DESCRIPTION
    Run it from anywhere; it works on the repo it lives in.

      1. git fetch, then compares what is installed (the manifest install.ps1 writes)
         with what the repo's upstream branch has.
      2. Lists the new versions and their CHANGELOG.md entries.
      3. Warns when Core changed a file that your Personal or Company layer overrides.
         Your override keeps winning, so you may want to copy the Core change into it.
         -ShowDiff prints the Core diff for each one.
      4. Asks, then runs git pull --ff-only and install.ps1 (or install.ps1 -Component dashboard).

    Versions live in core/VERSION (Core) and core/scripts/dashboard/VERSION (dashboard).
    The dashboard can be updated on its own; a full update includes it.

    The live dashboard runs "update.ps1 -Check -Json" to show an update notice, and
    "update.ps1 -Component <name> -Yes" when you click Update.

.EXAMPLE
    .\update.ps1
    Checks, shows what is new, asks, then updates everything.

.EXAMPLE
    .\update.ps1 -Component dashboard
    Updates only the dashboard. Agents, AGENTS.md, and opencode.json are left as they are.

.EXAMPLE
    .\update.ps1 -Check -ShowDiff
    Only reports, with the Core diff for every overridden file that changed.
#>
[CmdletBinding()]
param(
    [ValidateSet("all", "dashboard")]
    [string]$Component = "all",

    # Report only. Nothing is pulled or installed (the repo is still fetched).
    [switch]$Check,

    # With -Check: print one line of JSON instead of text.
    [switch]$Json,

    # Do not ask before updating.
    [switch]$Yes,

    # Print the Core diff for each overridden file that changed.
    [switch]$ShowDiff,

    # Compare with the local repo only (no git fetch).
    [switch]$NoFetch,

    # Passed to install.ps1. Same default.
    [string]$Target = (Join-Path $(if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }) ".config/opencode")
)

$ErrorActionPreference = "Stop"
$repo = $PSScriptRoot

# Windows PowerShell 5.1 wraps some arrays as {"value":[...],"Count":n} in JSON without this.
if ($PSVersionTable.PSVersion.Major -lt 6) { Remove-TypeData System.Array -ErrorAction SilentlyContinue }

function Read-Text {
    param([string]$Path)
    $text = [System.IO.File]::ReadAllText($Path)
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    return $text
}

function Invoke-Git {
    # Returns @{ ok; out } and never throws, so one failed git call does not end the check.
    param([string[]]$GitArgs)
    $out = & git -C $repo @GitArgs 2>&1
    return @{ ok = ($LASTEXITCODE -eq 0); out = (@($out) | ForEach-Object { "$_" }) -join "`n" }
}

function Get-At {
    # File contents at a commit, or $null.
    param([string]$Ref, [string]$Path)
    if (-not $Ref) { return $null }
    $r = Invoke-Git @("show", "$($Ref):$Path")
    if ($r.ok) { return $r.out } else { return $null }
}

function Compare-Version {
    # -1, 0, 1. Anything that does not parse sorts as 0.0.0.
    param([string]$A, [string]$B)
    $pa = @(("$A" -split '[^0-9]+') | Where-Object { $_ -ne "" } | ForEach-Object { [int]$_ })
    $pb = @(("$B" -split '[^0-9]+') | Where-Object { $_ -ne "" } | ForEach-Object { [int]$_ })
    for ($i = 0; $i -lt 3; $i++) {
        $x = if ($i -lt $pa.Count) { $pa[$i] } else { 0 }
        $y = if ($i -lt $pb.Count) { $pb[$i] } else { 0 }
        if ($x -lt $y) { return -1 }
        if ($x -gt $y) { return 1 }
    }
    return 0
}

# What each component covers in the repo, for "did anything change".
$paths = @{
    # Core is everything except the dashboard, which has its own version.
    core = @("core", "install.ps1", "update.ps1", ":(exclude)core/scripts/dashboard", ":(exclude)core/commands/dashboard.md")
    dashboard = @("core/scripts/dashboard", "core/commands/dashboard.md")
}
function Test-InComponent {
    param([string]$Name, [string]$File)
    $hit = $false
    foreach ($p in $paths[$Name]) {
        if ($p.StartsWith(":(exclude)")) { $x = $p.Substring(10); if ($File -eq $x -or $File.StartsWith("$x/")) { return $false } }
        elseif ($File -eq $p -or $File.StartsWith("$p/")) { $hit = $true }
    }
    return $hit
}

# ------------------------------------------------------------------ gather

$result = [ordered]@{
    ok = $true
    error = $null
    repo = $repo
    branch = $null
    upstream = $null
    behind = 0
    ahead = 0
    fetched = $false
    fetchError = $null
    checked = (Get-Date).ToString("o")
    components = [ordered]@{}
    overrides = @()
    changelog = @()
    command = "pwsh"
}
$result.command = $(if ($PSVersionTable.PSVersion.Major -lt 6) { "powershell" } else { "pwsh" })

function Stop-WithError {
    param([string]$Message)
    if ($Json) {
        $result.ok = $false
        $result.error = $Message
        [Console]::Out.Write((ConvertTo-Json -InputObject $result -Depth 8 -Compress))
        exit 0
    }
    Write-Host "update: $Message" -ForegroundColor Red
    exit 1
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Stop-WithError "git is not on PATH." }
if (-not (Invoke-Git @("rev-parse", "--git-dir")).ok) { Stop-WithError "$repo is not a git clone. Updates need the cloned repo (git clone, then install.ps1)." }

$manifestPath = Join-Path $Target "eng-agents/manifest.json"
$manifest = $null
if (Test-Path $manifestPath) {
    try { $manifest = (Read-Text $manifestPath) | ConvertFrom-Json } catch { $manifest = $null }
}
if (-not $manifest) { Stop-WithError "Nothing installed at $Target yet. Run .\install.ps1 first." }
if ($manifest.PSObject.Properties["source"] -and $manifest.source -and -not ((Resolve-Path $manifest.source -ErrorAction SilentlyContinue).Path -eq (Resolve-Path $repo).Path)) {
    Write-Warning "The install at $Target came from $($manifest.source), not this repo ($repo)."
}

$result.branch = (Invoke-Git @("rev-parse", "--abbrev-ref", "HEAD")).out
$up = Invoke-Git @("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
if ($up.ok) { $result.upstream = $up.out }

if ($result.upstream -and -not $NoFetch) {
    $remote = $result.upstream.Split("/")[0]
    $f = Invoke-Git @("fetch", "--quiet", $remote)
    if ($f.ok) { $result.fetched = $true } else { $result.fetchError = ($f.out -split "`n" | Select-Object -Last 1) }
}

$head = (Invoke-Git @("rev-parse", "HEAD")).out
$available = $head
if ($result.upstream) {
    $counts = Invoke-Git @("rev-list", "--left-right", "--count", "HEAD...@{u}")
    if ($counts.ok) {
        $n = $counts.out.Trim() -split '\s+'
        $result.ahead = [int]$n[0]
        $result.behind = [int]$n[1]
    }
    if ($result.behind -gt 0) { $available = (Invoke-Git @("rev-parse", "@{u}")).out }
}
if ($result.ahead -gt 0 -and $result.behind -gt 0) {
    $result.error = "This clone and $($result.upstream) have both changed. Merge or rebase it with git, then update."
}

$installed = @{}
if ($manifest.PSObject.Properties["components"] -and $manifest.components) {
    foreach ($p in $manifest.components.PSObject.Properties) { $installed[$p.Name] = $p.Value }
}

$versionFile = @{ core = "core/VERSION"; dashboard = "core/scripts/dashboard/VERSION" }
foreach ($name in @("core", "dashboard")) {
    $inst = $installed[$name]
    $instVersion = if ($inst) { "$($inst.version)" } else { $null }
    $instCommit = if ($inst) { "$($inst.commit)" } else { $null }
    $availVersion = (Get-At $available $versionFile[$name])
    $availVersion = if ($availVersion) { $availVersion.Trim() } else { "0.0.0" }

    $changed = @()
    $known = $false
    if ($instCommit -and (Invoke-Git @("cat-file", "-e", "$instCommit^{commit}")).ok) {
        $d = Invoke-Git (@("diff", "--name-only", $instCommit, $available, "--") + $paths[$name])
        if ($d.ok) { $known = $true; $changed = @($d.out -split "`n" | Where-Object { $_ }) }
    }
    # An install from before versioning, or a commit this clone does not have: compare versions only.
    $update = if ($known) { $changed.Count -gt 0 } else { (-not $instVersion) -or ((Compare-Version $instVersion $availVersion) -lt 0) }

    $result.components[$name] = [ordered]@{
        installed = $instVersion
        installedCommit = $instCommit
        available = $availVersion
        availableCommit = $available
        update = [bool]$update
        changedFiles = $changed.Count
        compared = $known
    }
}

# Core changes to files a Personal or Company layer overrides.
if ($manifest.PSObject.Properties["overrides"] -and $manifest.overrides) {
    foreach ($p in $manifest.overrides.PSObject.Properties) {
        $rel = $p.Name
        $comp = if (Test-InComponent "dashboard" "core/$rel") { "dashboard" } else { "core" }
        $c = $result.components[$comp]
        if (-not $c.update) { continue }
        $diffText = $null
        if ($c.compared) {
            $d = Invoke-Git @("diff", $c.installedCommit, $available, "--", "core/$rel")
            if (-not $d.ok -or -not $d.out) { continue }
            $diffText = $d.out
        }
        $lines = if ($diffText) { @($diffText -split "`n") } else { @() }
        $result.overrides += , ([ordered]@{
                file = $rel
                layer = "$($p.Value)"
                component = $comp
                diff = $(if ($lines.Count -gt 400) { (($lines | Select-Object -First 400) -join "`n") + "`n... ($($lines.Count - 400) more lines)" } else { $diffText })
            })
    }
}

# CHANGELOG.md entries newer than what is installed. Headings look like: ## Dashboard 1.1.0 (2026-10-20)
$log = Get-At $available "CHANGELOG.md"
if ($log) {
    $cur = $null
    foreach ($line in ($log -split "`r?`n")) {
        $m = [regex]::Match($line, '^##\s+(Core|Dashboard)\s+v?([0-9][0-9.]*)\s*(?:\((.*)\))?\s*$')
        if ($m.Success) {
            $comp = $m.Groups[1].Value.ToLowerInvariant()
            $inst = $result.components[$comp].installed
            $keep = (-not $inst) -or ((Compare-Version $inst $m.Groups[2].Value) -lt 0)
            $cur = if ($keep) { [ordered]@{ component = $comp; version = $m.Groups[2].Value; date = $m.Groups[3].Value; lines = @() } } else { $null }
            if ($cur) { $result.changelog += , $cur }
            continue
        }
        if ($line -match '^#') { $cur = $null; continue }
        if ($cur -and $line -match '^\s*[-*]\s+(.*)$') { $cur.lines += , $Matches[1] }
    }
}

# ------------------------------------------------------------------ report

$wanted = if ($Component -eq "dashboard") { @("dashboard") } else { @("core", "dashboard") }
$needed = @($wanted | Where-Object { $result.components[$_].update })
$relevantOverrides = @($result.overrides | Where-Object { $wanted -contains $_.component })

if ($Check -and $Json) {
    $out = ConvertTo-Json -InputObject $result -Depth 8 -Compress
    # ASCII only, so the console code page (Windows PowerShell 5.1) cannot garble it.
    $out = [regex]::Replace($out, '[^\x00-\x7F]', { param($m) '\u{0:x4}' -f [int][char]$m.Value })
    [Console]::Out.Write($out)
    [Console]::Out.Flush()
    exit 0
}

Write-Host "eng-agents update"
Write-Host "  Repo     : $repo ($($result.branch)$(if ($result.upstream) { " tracking $($result.upstream)" }))"
if ($result.fetchError) { Write-Warning "Could not fetch: $($result.fetchError). Comparing with what this clone already has." }
elseif (-not $result.upstream) { Write-Warning "This branch tracks no remote. Comparing with the local clone only." }
foreach ($name in @("core", "dashboard")) {
    $c = $result.components[$name]
    $label = if ($name -eq "core") { "Core     " } else { "Dashboard" }
    $state = if (-not $c.update) { "up to date" } elseif ($c.installed -eq $c.available) { "(newer changes, same version)" } else { "-> $($c.available)" }
    Write-Host "  ${label}: $(if ($c.installed) { $c.installed } else { 'unknown' }) $state"
}
if ($result.error) { Stop-WithError $result.error }

if ($result.changelog.Count) {
    Write-Host ""
    Write-Host "What's new:"
    foreach ($e in $result.changelog) {
        if ($wanted -notcontains $e.component) { continue }
        $title = if ($e.component -eq "core") { "Core" } else { "Dashboard" }
        Write-Host "  $title $($e.version)$(if ($e.date) { " ($($e.date))" })"
        foreach ($l in $e.lines) { Write-Host "    - $l" }
    }
}

if ($relevantOverrides.Count) {
    Write-Host ""
    Write-Warning "Core changed $($relevantOverrides.Count) file(s) that you override. Your copy keeps winning, so it will not get these changes:"
    foreach ($o in $relevantOverrides) {
        Write-Host "  - $($o.file) ($($o.layer) layer)"
        if ($ShowDiff -and $o.diff) {
            foreach ($l in ($o.diff -split "`n")) {
                $color = if ($l.StartsWith("+") -and -not $l.StartsWith("+++")) { "Green" } elseif ($l.StartsWith("-") -and -not $l.StartsWith("---")) { "Red" } else { "Gray" }
                Write-Host "      $l" -ForegroundColor $color
            }
        }
    }
    if (-not $ShowDiff) { Write-Host "  See the changes: .\update.ps1 -Check -ShowDiff" }
}

if (-not $needed.Count) {
    Write-Host ""
    Write-Host "Up to date."
    exit 0
}
if ($Check) {
    Write-Host ""
    Write-Host "Update with: .\update.ps1$(if ($Component -eq 'dashboard') { ' -Component dashboard' })"
    exit 0
}

if (-not $Yes) {
    $answer = Read-Host "`nUpdate $(if ($Component -eq 'dashboard') { 'the dashboard' } else { 'eng-agents' }) now? [y/N]"
    if ($answer -notmatch '^(y|yes)$') { Write-Host "Nothing changed."; exit 0 }
}

# ------------------------------------------------------------------ update

if ($result.behind -gt 0) {
    Write-Host "Pulling $($result.behind) commit(s) from $($result.upstream)..."
    $p = Invoke-Git @("pull", "--ff-only", "--quiet")
    if (-not $p.ok) { Stop-WithError "git pull failed: $(($p.out -split "`n" | Select-Object -Last 2) -join ' ') Fix it with git, then run update.ps1 again." }
}

$install = Join-Path $repo "install.ps1"
$installArgs = @{ Target = $Target }
if ($Component -eq "dashboard") { $installArgs["Component"] = "dashboard" }
# Reinstall with the same layer folders as last time (install.ps1 -Personal / -Company).
if ($manifest.PSObject.Properties["layers"]) {
    foreach ($l in $manifest.layers) {
        if (($l.name -eq "Personal" -or $l.name -eq "Company") -and $l.path -and (Test-Path $l.path)) { $installArgs[$l.name] = $l.path }
    }
}
Write-Host ""
& $install @installArgs
