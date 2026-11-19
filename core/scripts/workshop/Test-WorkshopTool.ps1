<#
.SYNOPSIS
  Offline checks for Invoke-WorkshopTool.ps1: it finds Workshop's home, port and agent token, sends only to
  127.0.0.1 with the agent token, builds the arguments, prints the result, and turns Workshop's errors into the
  NOWORKSHOP / NOTOOL / REFUSED / FAILED lines the /cloudflare command reads. Workshop is faked: no network.
  Run: pwsh -NoProfile -File core/scripts/workshop/Test-WorkshopTool.ps1   (also works in Windows PowerShell 5.1)
#>
$ErrorActionPreference = "Stop"

$failed = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = "") {
    if ($Ok) { Write-Output "ok   $Name" } else { Write-Output "FAIL $Name $Detail"; $script:failed++ }
}

$script = Join-Path $PSScriptRoot "Invoke-WorkshopTool.ps1"
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("wst-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
$token = ("ab" * 32)
# Globals: the fake runs inside Invoke-WorkshopTool.ps1, where $script: means that script.
$global:WstCalls = New-Object System.Collections.ArrayList
$global:WstReply = $null
$calls = $global:WstCalls

# The fake Workshop: Invoke-RestMethod is a function here, so the script's calls land in it.
function Invoke-RestMethod {
    param($Method, $Uri, $Headers, $ContentType, $Body, $TimeoutSec)
    $text = if ($Body -is [byte[]]) { [System.Text.Encoding]::UTF8.GetString($Body) } else { $Body }
    [void]$global:WstCalls.Add([pscustomobject]@{ Method = "$Method"; Uri = "$Uri"; Token = $Headers["X-Workshop-Agent-Token"]; Body = $text })
    if ($global:WstReply -is [scriptblock]) { return & $global:WstReply }
    return $global:WstReply
}
function Run([hashtable]$Params) {
    $global:WstCalls.Clear()
    $out = & $script -WorkshopHome $tmp @Params 2>&1 | Out-String
    return [pscustomobject]@{ Out = $out.Trim(); Code = $LASTEXITCODE }
}
# An error the way Invoke-RestMethod throws it, with Workshop's JSON body.
function Fail-With([int]$Status, [string]$Code, [string]$Message) {
    $ex = New-Object System.Exception "HTTP $Status"
    $ex | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{ StatusCode = $Status }) -Force
    $err = New-Object System.Management.Automation.ErrorRecord $ex, "fake", ([System.Management.Automation.ErrorCategory]::InvalidOperation), $null
    $err.ErrorDetails = New-Object System.Management.Automation.ErrorDetails ((@{ error = $Message; code = $Code } | ConvertTo-Json -Compress))
    throw $err
}

try {
    $r = Run @{ List = $true }
    Check "no agent token: NOWORKSHOP" ($r.Out -like "NOWORKSHOP:*" -and $r.Code -eq 1) $r.Out

    [IO.File]::WriteAllText((Join-Path $tmp "agent-token"), "$token`n")
    [IO.File]::WriteAllText((Join-Path $tmp "config.json"), '{"port": 4399}')

    $global:WstReply = [pscustomobject]@{ tools = @([pscustomobject]@{ connector = "cloudflare"; action = "dns.list"; title = "List DNS records in a zone" }) }
    $r = Run @{ List = $true }
    Check "list prints connector action: title" ($r.Out -eq "cloudflare dns.list: List DNS records in a zone") $r.Out
    Check "list asks 127.0.0.1 on the configured port" ($calls[0].Uri -eq "http://127.0.0.1:4399/api/tools" -and $calls[0].Method -eq "Get") $calls[0].Uri
    Check "sends the agent token" ($calls[0].Token -eq $token)

    $global:WstReply = [pscustomobject]@{ result = [pscustomobject]@{ zone = "example.org"; records = @() } }
    $r = Run @{ Connector = "cloudflare"; Action = "dns.list"; Arg = "zone=example.org,limit=5,proxied=true" }
    $sent = $calls[0].Body | ConvertFrom-Json
    Check "posts to the tool" ($calls[0].Uri -eq "http://127.0.0.1:4399/api/tools/cloudflare/dns.list" -and $calls[0].Method -eq "Post") $calls[0].Uri
    Check "-Arg pairs become typed args" ($sent.args.zone -eq "example.org" -and $sent.args.limit -eq 5 -and $sent.args.proxied -eq $true) $calls[0].Body
    Check "never sends confirm" ($calls[0].Body -notmatch 'confirm')
    Check "prints the result as JSON" ((($r.Out | ConvertFrom-Json).zone) -eq "example.org") $r.Out
    Check "never prints the token" ($r.Out -notmatch $token)

    $r = Run @{ Connector = "cloudflare"; Action = "dns.list"; Arg = @("zone=a.org", "type=A") }
    $sent = $calls[0].Body | ConvertFrom-Json
    Check "-Arg as a list works too" ($sent.args.zone -eq "a.org" -and $sent.args.type -eq "A") $calls[0].Body

    $f = Join-Path $tmp "propose.json"
    [IO.File]::WriteAllText($f, '{"title":"Add notes","changes":[{"op":"dns.create","zone":"example.org","type":"TXT","name":"x","content":"a,b \"quoted\""}]}')
    $global:WstReply = [pscustomobject]@{ result = [pscustomobject]@{ id = "cf-20261119-abc123"; status = "waiting" } }
    $r = Run @{ Connector = "cloudflare"; Action = "changes.propose"; ArgsFile = $f }
    $sent = $calls[0].Body | ConvertFrom-Json
    Check "-ArgsFile sends the file, quotes and commas intact" ($sent.args.changes[0].content -eq 'a,b "quoted"') $calls[0].Body
    Check "prints the change set id" ($r.Out -match 'cf-20261119-abc123') $r.Out

    $r = Run @{ Connector = "cloudflare"; Action = "dns.list"; Arg = "zone=a.org"; ArgsFile = $f }
    Check "only one way to pass arguments" ($r.Out -like "FAILED:*" -and $calls.Count -eq 0) $r.Out
    $r = Run @{ Connector = "cloudflare"; Action = "dns.list"; ArgsJson = "[1,2]" }
    Check "arguments must be an object" ($r.Out -like "FAILED:*must be a JSON object*" -and $calls.Count -eq 0) $r.Out

    $global:WstReply = { Fail-With 404 "not_found" "There is no changes.apply tool for agents in cloudflare." }
    $r = Run @{ Connector = "cloudflare"; Action = "changes.apply"; Arg = "id=cf-1" }
    Check "a missing tool is NOTOOL" ($r.Out -like "NOTOOL: There is no changes.apply tool*" -and $r.Code -eq 1) $r.Out
    $global:WstReply = { Fail-With 400 "bad_request" "Not saved. Fix these first: 1. other.net is not one of the zones." }
    $r = Run @{ Connector = "cloudflare"; Action = "changes.propose"; ArgsFile = $f }
    Check "a refusal is REFUSED with Workshop's words" ($r.Out -like "REFUSED: Not saved. Fix these first:*") $r.Out
    $global:WstReply = { Fail-With 503 "disabled" "The Cloudflare connector is off in work mode." }
    $r = Run @{ Connector = "cloudflare"; Action = "zones.list" }
    Check "off in work mode is NOTOOL" ($r.Out -like "NOTOOL:*work mode*") $r.Out
    $global:WstReply = { throw (New-Object System.Exception "No connection could be made") }
    $r = Run @{ List = $true }
    Check "nothing listening is NOWORKSHOP" ($r.Out -like "NOWORKSHOP: Workshop is not running on port 4399*") $r.Out

    [IO.File]::WriteAllText((Join-Path $tmp "agent-token"), "not-a-token")
    $r = Run @{ List = $true }
    Check "a bad token file is NOWORKSHOP, and nothing is sent" ($r.Out -like "NOWORKSHOP:*" -and $calls.Count -eq 0) $r.Out
}
finally {
    Remove-Variable -Name WstCalls, WstReply -Scope Global -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failed) { Write-Output "$failed check(s) failed."; exit 1 }
Write-Output "Invoke-WorkshopTool: all checks passed."
