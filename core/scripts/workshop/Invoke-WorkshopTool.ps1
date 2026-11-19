<#
.SYNOPSIS
    Runs one of Workshop's tools for agents: a read action a Workshop connector marks for agents (for example
    Cloudflare's dns.list or changes.propose), or a change it lets agents ask for. Prints the result as JSON.

.DESCRIPTION
    Agents never hold an outside system's token. Workshop does (in this computer's secret store), and this
    script asks Workshop on this computer to make the call (Workshop docs/agent-api.md, Tools for agents):

      POST http://127.0.0.1:<port>/api/tools/<connector>/<action>   with the agent token from <home>/agent-token

    <home> is WORKSHOP_HOME or ~/.workshop; the port comes from <home>/config.json (default 4380). The agent
    token runs read actions marked for agents and asks for changes marked "ask": nothing here can write to an
    outside system by itself, confirm a change, or change Workshop's settings. A change becomes a request that
    waits for a person in Workshop's Approvals; the result is {"approval": {"id": "ap-...", "status": "waiting"}}
    (or, when an always-allow rule the person made covers it, {"rule": ..., "result": ...}). Check on it later
    with -Approval <id>. The token is read from the file each run, sent only to 127.0.0.1, and never printed.

    Output: the action's result as JSON. On failure, one line starting with a code and a colon, then exit 1:
      NOWORKSHOP: Workshop is not installed or not running on this computer
      NOTOOL:     that connector is off, not ready, or has no such tool for agents
      REFUSED:    Workshop or the connector said no (the message says why)
      FAILED:     anything else

.PARAMETER List
    List the tools Workshop offers right now (connector, action, title). "(asks)" marks a change that waits for
    approval.

.PARAMETER Approval
    Where a change you asked for stands: {"id", "status": waiting, approved, rejected or failed, "title", and
    "result" once approved, "note" when rejected, "error" when it failed}. Never the arguments.

.PARAMETER Connector
    The connector id, for example cloudflare.

.PARAMETER Action
    The action, for example dns.list.

.PARAMETER Arg
    Arguments as name=value, several joined with commas (-Arg zone=example.org,type=CNAME). Whole numbers, true and
    false become numbers and booleans. A value with a comma in it goes in -ArgsFile instead. The simplest way from a shell: Windows PowerShell 5.1 drops the inner quotes
    of JSON passed to another program, so -ArgsJson is unreliable there.

.PARAMETER ArgsJson
    The action's arguments as a JSON object, for example '{"zone":"example.org"}'. Default {}.

.PARAMETER ArgsFile
    A file holding the arguments as a JSON object (use this for change sets: write .work/cf-<name>/propose.json,
    then pass it here).

.EXAMPLE
    .\Invoke-WorkshopTool.ps1 -List

.EXAMPLE
    .\Invoke-WorkshopTool.ps1 -Connector cloudflare -Action dns.list -Arg zone=example.org

.EXAMPLE
    .\Invoke-WorkshopTool.ps1 -Connector cloudflare -Action changes.propose -ArgsFile .work/cf-rally-domain/propose.json

.EXAMPLE
    .\Invoke-WorkshopTool.ps1 -Approval ap-20261119-1a2b3c4d
#>
[CmdletBinding(DefaultParameterSetName = "Run")]
param(
    [Parameter(ParameterSetName = "List", Mandatory = $true)][switch]$List,
    [Parameter(ParameterSetName = "Approval", Mandatory = $true)][ValidatePattern('^ap-[0-9]{8}-[0-9a-f]{8}$')][string]$Approval,
    [Parameter(ParameterSetName = "Run", Mandatory = $true)][ValidatePattern('^[a-z][a-z0-9-]{0,39}$')][string]$Connector,
    [Parameter(ParameterSetName = "Run", Mandatory = $true)][ValidatePattern('^[a-z][a-zA-Z0-9]*(\.[a-z][a-zA-Z0-9]*)*$')][string]$Action,
    [Parameter(ParameterSetName = "Run")][string[]]$Arg = @(),
    [Parameter(ParameterSetName = "Run")][string]$ArgsJson = "",
    [Parameter(ParameterSetName = "Run")][string]$ArgsFile = "",
    [string]$WorkshopHome = ""
)
$ErrorActionPreference = "Stop"

function Stop-With([string]$Code, [string]$Message) {
    Write-Output "${Code}: $Message"
    exit 1
}

. (Join-Path $PSScriptRoot "WorkshopCommon.ps1")

$agent = Get-WorkshopAgent $WorkshopHome
if ($agent.Problem -eq "missing") {
    Stop-With "NOWORKSHOP" "Workshop's agent token is missing ($($agent.TokenFile)). Install Workshop 1.11.0 or later and start it once (workshop up)."
}
if ($agent.Problem) { Stop-With "NOWORKSHOP" "Workshop's agent token file does not hold a token. Restart Workshop (workshop restart) to make a new one." }
$port = $agent.Port

function Invoke-Tool([string]$Method, [string]$Path, $Body) {
    try { return Invoke-WorkshopApi $agent $Method $Path $Body }
    catch {
        $e = Read-WorkshopError $_
        if (-not $e.Status) { Stop-With "NOWORKSHOP" "Workshop is not running on port $port. Start it with: workshop up" }
        $msg = if ($e.Message) { $e.Message } else { "HTTP $($e.Status)." }
        if ($e.Status -eq 404 -or $e.Code -eq "unavailable" -or $e.Code -eq "disabled") { Stop-With "NOTOOL" $msg }
        if ($e.Status -eq 401) { Stop-With "NOWORKSHOP" "$msg Restart Workshop (workshop restart) if this keeps happening." }
        if ($e.Status -in @(400, 403, 409)) { Stop-With "REFUSED" $msg }
        Stop-With "FAILED" $msg
    }
}

if ($List) {
    $r = Invoke-Tool "GET" "" $null
    $tools = @($r.tools)
    if (-not $tools.Count) { Write-Output "No tools right now. A connector with tools for agents (Cloudflare, GitHub, MCP servers) is off or not ready in Workshop's Settings."; exit 0 }
    foreach ($t in $tools) { Write-Output ("{0} {1}: {2}{3}" -f $t.connector, $t.action, $t.title, $(if ($t.asks) { " (asks)" } else { "" })) }
    exit 0
}

if ($Approval) {
    $r = Invoke-Tool "GET" "/approvals/$Approval" $null
    ConvertTo-Json -InputObject $r -Depth 30
    exit 0
}

if (@($ArgsJson, $ArgsFile, ($Arg -join "")) | Where-Object { $_ } | Select-Object -Skip 1) { Stop-With "FAILED" "Use one of -Arg, -ArgsJson or -ArgsFile." }
$argsText = "{}"
if ($Arg.Count) {
    $o = [ordered]@{}
    # -File passes "a=1,b=2" as one string and -Command as two; split both the same way.
    $pairs = @($Arg | ForEach-Object { $_ -split ',(?=[A-Za-z][A-Za-z0-9_]{0,39}=)' } | Where-Object { $_ })
    foreach ($a in $pairs) {
        $m = [regex]::Match($a, '^([A-Za-z][A-Za-z0-9_]{0,39})=(.*)$')
        if (-not $m.Success) { Stop-With "FAILED" "-Arg $a is not name=value." }
        $v = $m.Groups[2].Value
        if ($v -match '^-?\d{1,9}$') { $o[$m.Groups[1].Value] = [int]$v }
        elseif ($v -eq 'true' -or $v -eq 'false') { $o[$m.Groups[1].Value] = ($v -eq 'true') }
        else { $o[$m.Groups[1].Value] = $v }
    }
    $argsText = ConvertTo-Json -InputObject $o -Compress
}
elseif ($ArgsFile) {
    if (-not (Test-Path -LiteralPath $ArgsFile)) { Stop-With "FAILED" "No file $ArgsFile." }
    $argsText = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $ArgsFile).Path)
}
elseif ($ArgsJson) { $argsText = $ArgsJson }
try { $argsObj = $argsText | ConvertFrom-Json } catch { Stop-With "FAILED" "The arguments are not valid JSON: $($_.Exception.Message)" }
if ($null -eq $argsObj -or $argsObj -is [array] -or $argsObj -isnot [pscustomobject]) { Stop-With "FAILED" "The arguments must be a JSON object, like {""zone"":""example.org""}." }

$r = Invoke-Tool "POST" "/$Connector/$Action" @{ args = $argsObj }
ConvertTo-Json -InputObject $r.result -Depth 30
