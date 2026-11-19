<#
.SYNOPSIS
    Shared helpers for scripts that use Workshop's tools for agents: where Workshop is, its agent token, and one
    call to it. Dot-source it: . (Join-Path $PSScriptRoot "WorkshopCommon.ps1")

.DESCRIPTION
    Workshop holds outside systems' tokens (in this computer's secret store) and makes calls for agents
    (Workshop docs/agent-api.md, Tools for agents). These helpers find <home> (WORKSHOP_HOME or ~/.workshop), read
    the port from <home>/config.json (default 4380) and the agent token from <home>/agent-token, and call
    http://127.0.0.1:<port>/api/tools. The agent token runs reads marked for agents and asks for changes marked
    "ask" (those wait for a person in Workshop's Approvals). It is read from the file each run, sent only to
    127.0.0.1, and never printed or written anywhere.
#>

function Get-WorkshopHome {
    param([string]$Override = "")
    if ($Override) { return $Override }
    if ($env:WORKSHOP_HOME -and $env:WORKSHOP_HOME.Trim()) { return $env:WORKSHOP_HOME }
    $userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    return (Join-Path $userHome ".workshop")
}

# Where Workshop is and its agent token. Problem is "" when it can be used, else "missing" or "bad".
function Get-WorkshopAgent {
    param([string]$WorkshopHome = "")
    $wsHome = Get-WorkshopHome $WorkshopHome
    $tokenFile = Join-Path $wsHome "agent-token"
    $port = 4380
    $cfgFile = Join-Path $wsHome "config.json"
    if (Test-Path -LiteralPath $cfgFile) {
        try {
            $cfg = [System.IO.File]::ReadAllText($cfgFile) | ConvertFrom-Json
            if ($cfg.PSObject.Properties["port"] -and $cfg.port) { $port = [int]$cfg.port }
        }
        catch { }
    }
    $agent = [pscustomobject]@{ Home = $wsHome; TokenFile = $tokenFile; Port = $port; Base = "http://127.0.0.1:$port/api/tools"; Headers = $null; Problem = "" }
    if (-not (Test-Path -LiteralPath $tokenFile)) { $agent.Problem = "missing"; return $agent }
    $token = ([System.IO.File]::ReadAllText($tokenFile)).Trim()
    if ($token -notmatch '^[0-9a-f]{64}$') { $agent.Problem = "bad"; return $agent }
    $agent.Headers = @{ "X-Workshop-Agent-Token" = $token; "User-Agent" = "eng-agents" }
    return $agent
}

# Status, Code and Message from a failed call (Status is $null when nothing answered).
function Read-WorkshopError($Err) {
    $text = $null
    try { $text = $Err.ErrorDetails.Message } catch { }
    if (-not $text) {
        try {
            $stream = $Err.Exception.Response.GetResponseStream()
            $text = (New-Object System.IO.StreamReader($stream)).ReadToEnd()
        }
        catch { }
    }
    $msg = $null; $code = $null
    if ($text) { try { $j = $text | ConvertFrom-Json; $msg = $j.error; $code = $j.code } catch { } }
    $status = $null
    try { $status = [int]$Err.Exception.Response.StatusCode } catch { }
    return [pscustomobject]@{ Status = $status; Code = $code; Message = $msg }
}

# One call. $Path is after /api/tools ("" for the list, "/cloudflare/dns.list", "/approvals/ap-..."). Throws what
# Invoke-RestMethod throws; read it with Read-WorkshopError.
function Invoke-WorkshopApi {
    param($Agent, [string]$Method, [string]$Path, $Body, [int]$TimeoutSec = 120)
    $uri = "$($Agent.Base)$Path"
    if ($Method -eq "GET") { return Invoke-RestMethod -Method Get -Uri $uri -Headers $Agent.Headers -TimeoutSec $TimeoutSec }
    $json = ConvertTo-Json -InputObject $Body -Depth 30 -Compress
    return Invoke-RestMethod -Method Post -Uri $uri -Headers $Agent.Headers -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec $TimeoutSec
}

# True when Workshop is running and offers <connector> <action> to agents right now. Never throws.
function Test-WorkshopOffers {
    param($Agent, [string]$Connector, [string]$Action)
    if (-not $Agent -or $Agent.Problem) { return $false }
    try { $r = Invoke-WorkshopApi $Agent "GET" "" $null 5 } catch { return $false }
    return [bool](@($r.tools) | Where-Object { $_.connector -eq $Connector -and $_.action -eq $Action })
}
