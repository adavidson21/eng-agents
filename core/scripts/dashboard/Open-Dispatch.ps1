<#
.SYNOPSIS
    Opens Dispatch, Workshop's live view of .work and the opencode agents, in your browser.
    /dashboard runs this.

.DESCRIPTION
    Dispatch (the Agents app in Workshop, adavidson21/workshop) replaced the live dashboard
    that used to run from this folder. This script starts nothing and changes nothing.

      1. Reads Workshop's config.json (WORKSHOP_HOME, else ~/.workshop) for its port
         (default 4380) and asks http://127.0.0.1:<port>/api/health whether it is running.
      2. Not running: says how to start Workshop and exits with code 2. Nothing is opened.
      3. Running: opens Dispatch, at the item when -Id is given. The address comes from
         Dispatch.ps1: "dispatch": { "url": ... } in config.json if set, else Workshop on
         this computer in work mode, else https://workshop.alexisdavidson.org.

    The first output line says what happened. The last line is always the address.

.EXAMPLE
    .\Open-Dispatch.ps1

.EXAMPLE
    .\Open-Dispatch.ps1 -Id 41207
#>
[CmdletBinding()]
param(
    # A work item id (41207), a local id (L3), or a .work folder such as pr-512.
    [string]$Id,

    [string]$ConfigPath = (Join-Path $(if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }) ".config/eng-agents/config.json"),

    # Print the address but do not open a browser.
    [switch]$NoOpen
)

$ErrorActionPreference = "Stop"
$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $here "Dispatch.ps1")

if ($Id -and $Id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
    Write-Output "Not a work item id: $Id. Use a number such as 41207, a local id such as L3, or a .work folder such as pr-512."
    exit 1
}

$ws = Get-WorkshopConfig
$url = Get-DispatchUrl -Workshop $ws -ConfigPath $ConfigPath -Id $Id

$running = $false
try {
    $health = Invoke-RestMethod -Uri "http://127.0.0.1:$($ws.Port)/api/health" -TimeoutSec 3
    $running = ($health -and $health.PSObject.Properties["app"] -and $health.app -eq "workshop-agent")
}
catch { $running = $false }

if (-not $running) {
    if ($ws.Found) {
        Write-Output "Workshop is not running on this computer (nothing answered on port $($ws.Port)). Start it with: workshop up (or Workshop in the Start menu), then run /dashboard again."
    }
    else {
        Write-Output "Workshop is not installed on this computer. Dispatch, the live view of your work, runs in Workshop: see https://github.com/adavidson21/workshop#dispatch to install it, then run /dashboard again."
    }
    Write-Output "Without Workshop, /dashboard static builds a snapshot page and /status shows where each item is."
    Write-Output $url
    exit 2
}

Write-Output "Opening Dispatch$(if ($Id) { " at $Id" }) in Workshop."
if (-not $ws.OpencodeOn) {
    Write-Output "The opencode connector is off in Workshop. Turn it on in Workshop's Settings, with this workspace folder, so Dispatch can see .work."
}

if (-not $NoOpen) {
    try {
        if ($PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows) { Start-Process $url }
        elseif ($IsMacOS) { & open $url }
        elseif (Get-Command xdg-open -ErrorAction SilentlyContinue) { & xdg-open $url 2>$null | Out-Null }
        else { Write-Output "Could not open a browser. Open the address below yourself." }
    }
    catch { Write-Output "Could not open a browser. Open the address below yourself." }
}

Write-Output $url
