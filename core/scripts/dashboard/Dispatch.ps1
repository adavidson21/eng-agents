# Where Dispatch is. Dispatch (the Agents app in adavidson21/workshop) is the live view of .work
# and the opencode agents; it replaced the live dashboard that used to run from this folder.
# Dot-sourced by Open-Dispatch.ps1 (/dashboard) and New-Dashboard.ps1 (the static page's link).
# Reads two files and makes no network calls.

function Get-WorkshopConfig {
    # Workshop on this computer: <home>/config.json, where <home> is WORKSHOP_HOME or ~/.workshop
    # (Workshop docs/config.md). Found is $false when Workshop was never installed here.
    $userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    $homeDir = if ($env:WORKSHOP_HOME -and $env:WORKSHOP_HOME.Trim()) { $env:WORKSHOP_HOME } else { Join-Path $userHome ".workshop" }
    $file = Join-Path $homeDir "config.json"
    $cfg = $null
    if (Test-Path -LiteralPath $file) {
        try { $cfg = [System.IO.File]::ReadAllText($file) | ConvertFrom-Json } catch { $cfg = $null }
    }
    $port = 4380
    if ($cfg -and $cfg.PSObject.Properties["port"] -and $cfg.port) { $port = [int]$cfg.port }
    $workMode = $false
    if ($cfg -and $cfg.PSObject.Properties["features"] -and $cfg.features -and $cfg.features.PSObject.Properties["workMode"]) {
        $workMode = ($cfg.features.workMode -eq $true)
    }
    $opencodeOn = $false
    if ($cfg -and $cfg.PSObject.Properties["connectors"] -and $cfg.connectors -and $cfg.connectors.PSObject.Properties["opencode"]) {
        $oc = $cfg.connectors.opencode
        $opencodeOn = [bool]($oc -and $oc.PSObject.Properties["enabled"] -and $oc.enabled -eq $true)
    }
    return [pscustomobject]@{ Found = [bool]$cfg; File = $file; Port = $port; WorkMode = $workMode; OpencodeOn = $opencodeOn }
}

function Get-DispatchUrl {
    # The address of Dispatch, at one item when -Id is given (Workshop's #/agents/<id> route).
    # Workshop's address, in order:
    #   1. "dispatch": { "url": "<Workshop's address>" } in the eng-agents config.json
    #   2. Workshop on this computer (http://127.0.0.1:<port>/) in work mode, where no website can reach it
    #   3. https://workshop.alexisdavidson.org
    param($Workshop, [string]$ConfigPath, [string]$Id)
    $base = $null
    if ($ConfigPath -and (Test-Path -LiteralPath $ConfigPath)) {
        try {
            $c = [System.IO.File]::ReadAllText($ConfigPath) | ConvertFrom-Json
            if ($c.PSObject.Properties["dispatch"] -and $c.dispatch -and $c.dispatch.PSObject.Properties["url"] -and $c.dispatch.url) { $base = "$($c.dispatch.url)" }
        }
        catch { $base = $null }
    }
    if (-not $base) {
        $base = if ($Workshop -and $Workshop.WorkMode) { "http://127.0.0.1:$($Workshop.Port)/" } else { "https://workshop.alexisdavidson.org/" }
    }
    $url = $base.Split("#")[0].TrimEnd("/") + "/#/agents"
    if ($Id) { $url += "/" + [uri]::EscapeDataString($Id) }
    return $url
}
