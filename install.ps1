<#
.SYNOPSIS
    Installs eng-agents into your opencode global config by layering
    Core, then Personal, then Company.

.DESCRIPTION
    Layers (later wins):
      1. Core     <repo>\core                                   always
      2. Personal <repo>\personal  (or -Personal <path>)        if it exists
      3. Company  %USERPROFILE%\.config\eng-agents\overlay      if it exists
                  (on Mac/Linux: ~/.config/eng-agents/overlay)

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

    Shell permission tiers (bash rules shared by every agent):
      <layer>\permissions\read.json     read-only commands
      <layer>\permissions\build.json    build, test, lint
      <layer>\permissions\guards.json   asks and denies, always placed last
      Each tier is merged across layers (a later layer adds keys or changes a
      value). A line "{{BASH:<tier>}}": include in an agent file or opencode.json
      is replaced with that tier's rules, so one entry reaches every agent.

    Tokens replaced in every installed .md and .json:
      {{ENG_HOME}}  full path of <Target>\eng-agents
      {{ENG_CONFIG}} full path of ~/.config/eng-agents (config.json, overlay,
                    global memory.md)
      {{PS}}        "powershell" when installed from Windows PowerShell 5.1,
                    "pwsh" when installed from PowerShell 7 (Mac, Linux, or Windows)

.EXAMPLE
    .\install.ps1

.EXAMPLE
    .\install.ps1 -DryRun

.EXAMPLE
    .\install.ps1 -Target "$env:APPDATA\opencode" -Personal C:\tools\eng-agents-personal
#>
[CmdletBinding()]
param(
    [string]$Target = (Join-Path $(if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }) ".config/opencode"),
    [string]$Personal = (Join-Path $PSScriptRoot "personal"),
    [string]$Company = (Join-Path $(if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }) ".config/eng-agents/overlay"),
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
    return $Text.Replace("{{ENG_HOME}}", $script:EngHomeToken).Replace("{{ENG_CONFIG}}", $script:EngConfigToken).Replace("{{PS}}", $script:PsToken)
}

function Get-Tier {
    param([string]$Name, [string]$Where)
    if (-not $script:Tiers.Contains($Name)) { throw "Unknown permission tier '{{BASH:$Name}}' in $Where. Known tiers: $(@($script:Tiers.Keys) -join ', ')" }
    return $script:Tiers[$Name]
}

function Expand-BashTiersText {
    # YAML frontmatter: a line '    "{{BASH:read}}": include' becomes one line per rule, same indent.
    param([string]$Text, [string]$Where)
    $lines = $Text -split "`r?`n"
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        $m = [regex]::Match($line, '^(\s*)"\{\{BASH:([A-Za-z0-9_-]+)\}\}"\s*:.*$')
        if (-not $m.Success) { $out.Add($line); continue }
        $indent = $m.Groups[1].Value
        $tier = Get-Tier $m.Groups[2].Value $Where
        foreach ($k in @($tier.Keys)) {
            $key = $k.Replace("\", "\\").Replace('"', '\"')
            $out.Add("$indent""$key"": $($tier[$k])")
        }
    }
    return ($out -join "`n")
}

function Expand-BashTiersMap {
    # opencode.json: a key "{{BASH:read}}" inside a bash map becomes that tier's rules, in place.
    param($Map, [string]$Where)
    $result = [ordered]@{}
    foreach ($k in @($Map.Keys)) {
        $m = [regex]::Match([string]$k, '^\{\{BASH:([A-Za-z0-9_-]+)\}\}$')
        if ($m.Success) {
            $tier = Get-Tier $m.Groups[1].Value $Where
            foreach ($tk in @($tier.Keys)) { if ($result.Contains($tk)) { $result.Remove($tk) }; $result[$tk] = $tier[$tk] }
        }
        else {
            if ($result.Contains($k)) { $result.Remove($k) }
            $result[$k] = $Map[$k]
        }
    }
    return $result
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
        # Assign directly: an "if" expression would unroll a one-item list into a plain value.
        $b = $null
        if ($Base.Contains($k)) { $b = $Base[$k] }
        $o = $Over[$k]
        if (($b -is [System.Collections.Specialized.OrderedDictionary]) -and ($o -is [System.Collections.Specialized.OrderedDictionary])) {
            Merge-Ordered $b $o
        }
        elseif (($b -is [array]) -and ($o -is [array])) {
            # Lists (for example "instructions") are combined, not replaced.
            $list = @($b)
            foreach ($item in $o) { if ($list -notcontains $item) { $list += , $item } }
            $Base[$k] = $list
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

# Refuse to run as root on Mac/Linux: files would be owned by root and opencode could not use them.
if ($PSVersionTable.PSEdition -eq "Core" -and -not $IsWindows) {
    if ((& id -u) -eq "0") {
        throw "Do not run this with sudo. Files would be owned by root. If you got a permission error without sudo, fix ownership instead: sudo chown -R `$(whoami) ~/.config ~/.local ~/.cache"
    }
}

$coreDir = Join-Path $PSScriptRoot "core"
if (-not (Test-Path $coreDir)) { throw "Core folder not found at $coreDir. Run this script from the eng-agents repo." }

# A layer counts only if it has something to install. A folder holding just TODO.md is skipped.
function Test-LayerContent {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    foreach ($name in @("AGENTS.md", "opencode.json", "agents", "commands", "templates", "scripts", "permissions")) {
        if (Test-Path (Join-Path $Path $name)) { return $true }
    }
    return $false
}

$layers = @([pscustomobject]@{ Name = "Core"; Path = $coreDir })
if (-not $CoreOnly) {
    if (Test-LayerContent $Personal) { $layers += [pscustomobject]@{ Name = "Personal"; Path = (Resolve-Path $Personal).Path } }
    else { Write-Warning "Personal layer is empty or missing at $Personal. Skipping it. (See personal/TODO.md.)" }

    if (Test-LayerContent $Company) { $layers += [pscustomobject]@{ Name = "Company"; Path = (Resolve-Path $Company).Path } }
    else { Write-Warning "Company overlay not found at $Company. Skipping it. (Expected on a home machine. See company/TODO.md.)" }
}

$engHome = Join-Path $Target "eng-agents"
$script:EngHomeToken = $engHome.Replace("\", "/")
$engConfig = Join-Path $(if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }) ".config/eng-agents"
$script:EngConfigToken = $engConfig.Replace("\", "/")
$script:PsToken = if ($PSVersionTable.PSEdition -eq "Core") { "pwsh" } else { "powershell" }
$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$backupDir = Join-Path $engHome "backup\$stamp"

Write-Host "eng-agents install"
Write-Host "  Target : $Target"
Write-Host "  Layers : $(($layers | ForEach-Object { "$($_.Name) ($($_.Path))" }) -join ' -> ')"
if ($DryRun) { Write-Host "  DRY RUN: nothing will be written." }
Write-Host ""

# ---------------------------------------------- shell permission tiers

$script:Tiers = [ordered]@{}
foreach ($layer in $layers) {
    $dir = Join-Path $layer.Path "permissions"
    if (-not (Test-Path $dir)) { continue }
    foreach ($f in (Get-ChildItem -Path $dir -Filter *.json -File | Sort-Object Name)) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $rules = Read-JsonOrdered $f.FullName -ExpandTokens
        if (-not $script:Tiers.Contains($name)) { $script:Tiers[$name] = [ordered]@{} }
        elseif ($layer.Name -ne "Core") { Write-Host "  permissions: $($layer.Name) adds to tier '$name'" }
        Merge-Ordered $script:Tiers[$name] $rules
    }
}

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
$oldBashKeys = $null
if (Test-Path $manifestPath) {
    $parsed = (Read-Text $manifestPath) | ConvertFrom-Json
    if ($parsed -is [System.Management.Automation.PSCustomObject] -and $parsed.PSObject.Properties["files"]) {
        foreach ($entry in $parsed.files) { $oldManifest += $entry }
        $oldBashKeys = @()
        foreach ($entry in $parsed.bashKeys) { $oldBashKeys += $entry }
    }
    else {
        # Older installs wrote a plain list of files.
        # foreach unrolls the array the same way in Windows PowerShell 5.1 and PowerShell 7.
        foreach ($entry in $parsed) { $oldManifest += $entry }
    }
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
        $text = Expand-Tokens (Read-Text $src)
        if ($rel -like "agents/*") { $text = Expand-BashTiersText $text $src }
        Write-Utf8 $dest $text
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
$layerBash = $null
if ($layerConfig.Contains("permission") -and $layerConfig["permission"].Contains("bash")) {
    $layerBash = Expand-BashTiersMap $layerConfig["permission"]["bash"] "opencode.json"
    $layerConfig["permission"]["bash"] = $layerBash
}
$newBashKeys = if ($layerBash) { @($layerBash.Keys) } else { @() }

function Merge-Bash {
    # Bash rules are order-sensitive (last match wins), so eng-agents rules are written as one
    # block in layer order. Rules you added to the installed file yourself are kept, placed right
    # after "*" so the eng-agents asks and denies still win. Rules from an earlier install that
    # no longer exist in any layer are dropped.
    param($Config)
    if (-not $layerBash) { return }
    if (-not $Config.Contains("permission")) { $Config["permission"] = [ordered]@{} }
    $existing = if ($Config["permission"].Contains("bash")) { $Config["permission"]["bash"] } else { $null }
    $own = [ordered]@{}
    if ($existing -is [System.Collections.Specialized.OrderedDictionary]) {
        foreach ($k in @($existing.Keys)) {
            if ($newBashKeys -contains $k) { continue }
            if ($oldBashKeys -and ($oldBashKeys -contains $k)) { continue }
            $own[$k] = $existing[$k]
        }
    }
    $merged = [ordered]@{}
    $first = $true
    foreach ($k in @($layerBash.Keys)) {
        $merged[$k] = $layerBash[$k]
        if ($first) {
            foreach ($ok in @($own.Keys)) { $merged[$ok] = $own[$ok] }
            $first = $false
        }
    }
    if ($own.Count -gt 0) { Write-Host "  opencode.json: kept $($own.Count) shell rule(s) you added by hand" }
    $Config["permission"]["bash"] = $merged
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
        Merge-Bash $config
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
    Write-Utf8 $manifestPath (ConvertTo-Json -Depth 4 -InputObject ([ordered]@{ files = @($newManifest); bashKeys = @($newBashKeys) }))
}

# ---------------------------------------------- readiness checks

Write-Host ""
Write-Host "Checks:"
$cfg = Join-Path $engConfig "config.json"
if (Test-Path $cfg) {
    Write-Host "  [ok]   ADO config found: $cfg"
    try {
        $c = (Read-Text $cfg) | ConvertFrom-Json
        $envVars = @()
        $topPat = if ($c.PSObject.Properties["patEnv"]) { $c.patEnv } else { "ADO_PAT" }
        $topAuth = if ($c.PSObject.Properties["auth"]) { $c.auth } else { "pat" }
        if ($c.PSObject.Properties["connections"]) {
            $names = @($c.connections.PSObject.Properties | ForEach-Object { $_.Name })
            Write-Host "  [ok]   ADO connections: $($names -join ', ')$(if ($c.PSObject.Properties['default']) { " (default: $($c.default))" })"
            foreach ($p in $c.connections.PSObject.Properties) {
                $auth = if ($p.Value.PSObject.Properties["auth"]) { $p.Value.auth } else { $topAuth }
                if ($auth -eq "windows") { continue }
                $envVars += $(if ($p.Value.PSObject.Properties["patEnv"]) { $p.Value.patEnv } else { $topPat })
            }
        }
        elseif ($topAuth -ne "windows") { $envVars += $topPat }
        foreach ($v in @($envVars | Select-Object -Unique)) {
            if ([Environment]::GetEnvironmentVariable($v)) { Write-Host "  [ok]   $v is set" }
            else { Write-Host "  [todo] $v is not set. /start will use offline mode for connections that need it." }
        }
    }
    catch { Write-Host "  [todo] Could not read $cfg ($($_.Exception.Message))" }
}
else {
    Write-Host "  [todo] ADO config missing: $cfg (copy core\scripts\ado\config.example.json). /start will use offline mode until then."
    if ($env:ADO_PAT) { Write-Host "  [ok]   ADO_PAT is set" }
    else { Write-Host "  [todo] ADO_PAT is not set. /start will use offline mode until then." }
}

$mem = Join-Path $engConfig "memory.md"
if (Test-Path $mem) { Write-Host "  [ok]   Global memory: $mem" }
else { Write-Host "  [info] No global memory yet. /memory -global creates $mem" }

$mmdc = Get-Command mmdc -ErrorAction SilentlyContinue | Select-Object -First 1
if ($mmdc) { Write-Host "  [ok]   mermaid-cli: $($mmdc.Source)" }
else { Write-Host "  [info] mermaid-cli not installed. /tsd will check diagrams by checklist only. To render-check: npm install -g @mermaid-js/mermaid-cli" }

if ($DryRun) { Write-Host "`nDry run complete. Nothing was written." }
else { Write-Host "`nDone. Restart opencode to load the changes." }
