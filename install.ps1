<#
.SYNOPSIS
    Installs eng-agents into your opencode global config by layering
    Core, then Personal, then Company.

.DESCRIPTION
    Layers (later wins):
      1. Core     <repo>\core                                   always
      2. Personal <repo>\personal  (or -Personal <path>)        if it exists
      3. Company  %USERPROFILE%\.config\eng-agents\overlay      if it exists

    What gets written to -Target (your opencode config folder):
      agents\*.md, commands\*.md   later layer replaces same-named file
      AGENTS.md                    each layer appended as its own section,
                                   inside eng-agents markers. Your own text
                                   outside the markers is kept.
      opencode.json                permission keys merged into your existing
                                   file. Provider and model settings are kept.
      eng-agents\templates\        templates (later layer replaces same name)
      eng-agents\scripts\          scripts
      eng-agents\manifest.json     what was installed, so removed files get
                                   cleaned up next time
      eng-agents\backup\<time>\    copies of anything overwritten

    The token {{ENG_HOME}} in any installed .md or .json is replaced with the
    full path of <Target>\eng-agents.

.EXAMPLE
    .\install.ps1

.EXAMPLE
    .\install.ps1 -DryRun

.EXAMPLE
    .\install.ps1 -Target "$env:APPDATA\opencode" -Personal C:\tools\eng-agents-personal
#>
[CmdletBinding()]
param(
    [string]$Target = (Join-Path $env:USERPROFILE ".config\opencode"),
    [string]$Personal = (Join-Path $PSScriptRoot "personal"),
    [string]$Company = (Join-Path $env:USERPROFILE ".config\eng-agents\overlay"),
    [switch]$CoreOnly,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# ------------------------------------------------------------------ helpers

function Write-Utf8 {
    param([string]$Path, [string]$Content)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

function Read-Text {
    param([string]$Path)
    $text = [System.IO.File]::ReadAllText($Path)
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    return $text
}

function Expand-Tokens {
    param([string]$Text)
    return $Text.Replace("{{ENG_HOME}}", $script:EngHomeToken)
}

function ConvertTo-Ordered {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $h = [ordered]@{}
        foreach ($p in $Value.PSObject.Properties) { $h[$p.Name] = ConvertTo-Ordered $p.Value }
        return $h
    }
    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
        $list = @()
        foreach ($v in $Value) { $list += , (ConvertTo-Ordered $v) }
        return , $list
    }
    return $Value
}

function Merge-Ordered {
    # Merges $Over into $Base in place. Existing keys keep their position, so
    # "last matching rule wins" ordering in permission blocks stays predictable.
    param($Base, $Over)
    foreach ($k in @($Over.Keys)) {
        $b = if ($Base.Contains($k)) { $Base[$k] } else { $null }
        $o = $Over[$k]
        if (($b -is [System.Collections.Specialized.OrderedDictionary]) -and ($o -is [System.Collections.Specialized.OrderedDictionary])) {
            Merge-Ordered $b $o
        }
        else {
            $Base[$k] = $o
        }
    }
}

function Read-JsonOrdered {
    param([string]$Path, [switch]$ExpandTokens)
    $raw = Read-Text $Path
    if ($ExpandTokens) { $raw = Expand-Tokens $raw }
    return ConvertTo-Ordered ($raw | ConvertFrom-Json)
}

# ------------------------------------------------------------------ layers

$coreDir = Join-Path $PSScriptRoot "core"
if (-not (Test-Path $coreDir)) { throw "Core folder not found at $coreDir. Run this script from the eng-agents repo." }

$layers = @([pscustomobject]@{ Name = "Core"; Path = $coreDir })
if (-not $CoreOnly) {
    if (Test-Path $Personal) { $layers += [pscustomobject]@{ Name = "Personal"; Path = (Resolve-Path $Personal).Path } }
    else { Write-Warning "Personal layer not found at $Personal. Skipping it." }

    if (Test-Path $Company) { $layers += [pscustomobject]@{ Name = "Company"; Path = (Resolve-Path $Company).Path } }
    else { Write-Warning "Company overlay not found at $Company. Skipping it. (Expected on a home machine.)" }
}

$engHome = Join-Path $Target "eng-agents"
$script:EngHomeToken = $engHome.Replace("\", "/")
$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$backupDir = Join-Path $engHome "backup\$stamp"

Write-Host "eng-agents install"
Write-Host "  Target : $Target"
Write-Host "  Layers : $(($layers | ForEach-Object { "$($_.Name) ($($_.Path))" }) -join ' -> ')"
if ($DryRun) { Write-Host "  DRY RUN: nothing will be written." }
Write-Host ""

# ---------------------------------------------- resolve files across layers

# Key = path relative to the layer folder (forward slashes). Value = source file.
$files = [ordered]@{}
foreach ($layer in $layers) {
    foreach ($kind in @("agents", "commands", "templates", "scripts")) {
        $dir = Join-Path $layer.Path $kind
        if (-not (Test-Path $dir)) { continue }
        Get-ChildItem -Path $dir -Recurse -File | ForEach-Object {
            $rel = $_.FullName.Substring($layer.Path.Length).TrimStart("\", "/").Replace("\", "/")
            if ($files.Contains($rel) -and $layer.Name -ne "Core") {
                Write-Host "  override: $rel ($($layer.Name))"
            }
            $files[$rel] = $_.FullName
        }
    }
}

# Where each relative path lands under Target.
function Get-Destination {
    param([string]$Rel)
    if ($Rel -like "agents/*" -or $Rel -like "commands/*") { return Join-Path $Target $Rel }
    return Join-Path $engHome $Rel
}

# ---------------------------------------------- previous manifest cleanup

$manifestPath = Join-Path $engHome "manifest.json"
$oldManifest = @()
if (Test-Path $manifestPath) {
    # foreach unrolls the array the same way in Windows PowerShell 5.1 and PowerShell 7.
    foreach ($entry in ((Read-Text $manifestPath) | ConvertFrom-Json)) { $oldManifest += $entry }
}

$newManifest = @($files.Keys)
$stale = @($oldManifest | Where-Object { $newManifest -notcontains $_ })

function Backup-File {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path $Path)) { return }
    if ($DryRun) { Write-Host "  would back up: $Path"; return }
    $dest = Join-Path $backupDir $Name
    $dir = Split-Path -Parent $dest
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item $Path $dest -Force
}

foreach ($rel in $stale) {
    $dest = Get-Destination $rel
    if (Test-Path $dest) {
        Write-Host "  remove (no longer in any layer): $rel"
        Backup-File $dest $rel
        if (-not $DryRun) { Remove-Item $dest -Force }
    }
}

# ---------------------------------------------- copy agents, commands, templates, scripts

$count = 0
foreach ($rel in $files.Keys) {
    $src = $files[$rel]
    $dest = Get-Destination $rel

    # Never silently overwrite a file we did not install before.
    if ((Test-Path $dest) -and ($oldManifest -notcontains $rel)) {
        Write-Warning "Replacing a file eng-agents did not create: $dest (backed up)"
        Backup-File $dest $rel
    }

    if ($DryRun) { Write-Host "  would write: $dest"; $count++; continue }

    $ext = [System.IO.Path]::GetExtension($src).ToLowerInvariant()
    if ($ext -eq ".md" -or $ext -eq ".json") {
        Write-Utf8 $dest (Expand-Tokens (Read-Text $src))
    }
    else {
        $dir = Split-Path -Parent $dest
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Copy-Item $src $dest -Force
    }
    $count++
}
Write-Host "  files: $count written"

# ---------------------------------------------- AGENTS.md (sections, inside markers)

$begin = "<!-- eng-agents:begin (generated by install.ps1. Edit the layer files, not this block.) -->"
$end = "<!-- eng-agents:end -->"

$sections = @()
foreach ($layer in $layers) {
    $p = Join-Path $layer.Path "AGENTS.md"
    if (-not (Test-Path $p)) { continue }
    $body = Expand-Tokens (Read-Text $p)
    # Strip HTML comments: they are notes for you, not instructions for the model.
    $body = [regex]::Replace($body, "<!--[\s\S]*?-->", "")
    if (($layer.Name -ne "Core") -and ($body -match "TODO\(you\)")) { Write-Warning "$($layer.Name) AGENTS.md still contains TODO(you) items: $p" }
    $sections += "# eng-agents: $($layer.Name) layer`n`n$($body.Trim())`n"
}
$block = "$begin`n`n$($sections -join "`n")`n$end"

$agentsPath = Join-Path $Target "AGENTS.md"
if (Test-Path $agentsPath) {
    $existing = Read-Text $agentsPath
    Backup-File $agentsPath "AGENTS.md"
    $bi = $existing.IndexOf("<!-- eng-agents:begin")
    $ei = $existing.IndexOf($end)
    if ($bi -ge 0 -and $ei -gt $bi) {
        $merged = $existing.Substring(0, $bi) + $block + $existing.Substring($ei + $end.Length)
    }
    else {
        $merged = $existing.TrimEnd() + "`n`n" + $block + "`n"
    }
}
else {
    $merged = $block + "`n"
}
if ($DryRun) { Write-Host "  would write: $agentsPath ($($sections.Count) sections)" }
else { Write-Utf8 $agentsPath $merged; Write-Host "  AGENTS.md: $($sections.Count) sections" }

# ---------------------------------------------- opencode.json (merge permissions)

$jsonPath = Join-Path $Target "opencode.json"
$jsoncPath = Join-Path $Target "opencode.jsonc"

$layerConfig = [ordered]@{}
foreach ($layer in $layers) {
    $p = Join-Path $layer.Path "opencode.json"
    if (Test-Path $p) { Merge-Ordered $layerConfig (Read-JsonOrdered $p -ExpandTokens) }
}

$writeSidecar = $false
if (Test-Path $jsoncPath) {
    Write-Warning "Found opencode.jsonc. It may contain comments, so it was not modified."
    $writeSidecar = $true
}
elseif (Test-Path $jsonPath) {
    try {
        $config = Read-JsonOrdered $jsonPath
        Backup-File $jsonPath "opencode.json"
        Merge-Ordered $config $layerConfig
        if ($DryRun) { Write-Host "  would merge permissions into: $jsonPath" }
        else { Write-Utf8 $jsonPath ($config | ConvertTo-Json -Depth 32); Write-Host "  opencode.json: permissions merged (other settings kept)" }
    }
    catch {
        Write-Warning "Could not parse $jsonPath ($($_.Exception.Message)). It was not modified."
        $writeSidecar = $true
    }
}
else {
    if ($DryRun) { Write-Host "  would write: $jsonPath" }
    else { Write-Utf8 $jsonPath ($layerConfig | ConvertTo-Json -Depth 32); Write-Host "  opencode.json: created" }
}

if ($writeSidecar) {
    $sidecar = Join-Path $Target "opencode.eng-agents.json"
    if (-not $DryRun) { Write-Utf8 $sidecar ($layerConfig | ConvertTo-Json -Depth 32) }
    Write-Warning "Merge the 'permission' block from $sidecar into your opencode config by hand."
}

# ---------------------------------------------- manifest

if (-not $DryRun) {
    Write-Utf8 $manifestPath (ConvertTo-Json -InputObject $newManifest)
}

# ---------------------------------------------- readiness checks

Write-Host ""
Write-Host "Checks:"
$cfg = Join-Path $env:USERPROFILE ".config\eng-agents\config.json"
if (Test-Path $cfg) { Write-Host "  [ok]   ADO config found: $cfg" }
else { Write-Host "  [todo] ADO config missing: $cfg (copy core\scripts\ado\config.example.json). /start will use offline mode until then." }

if ($env:ADO_PAT) { Write-Host "  [ok]   ADO_PAT is set" }
else { Write-Host "  [todo] ADO_PAT is not set. /start will use offline mode until then." }

if ($DryRun) { Write-Host "`nDry run complete. Nothing was written." }
else { Write-Host "`nDone. Restart opencode to load the changes." }
