<#
.SYNOPSIS
    Shared ADO connection helpers for the eng-agents scripts. Dot-source it:

        . (Join-Path $PSScriptRoot "AdoConnection.ps1")

.DESCRIPTION
    Reads config.json (see config.example.json) and picks one connection, in this order:
      1. -From <connection name>
      2. -From <repo folder>: a "paths" mapping that matches the repo's full path,
         otherwise the collection in the repo's git remote URL
      3. A "paths" mapping that matches the current folder
      4. The "default" connection
      5. The only connection, if there is just one
    If none of these decide, it fails with a line starting "AMBIGUOUS:" that lists the
    connection names. An unknown -From fails with a line starting "UNKNOWN:".

    The PAT comes from an environment variable (ADO_PAT unless the connection sets patEnv).
    It is only ever put in the Authorization header and never printed.
#>

function Get-AdoProp {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

function ConvertTo-AdoPathKey {
    # Lowercase, forward slashes, no trailing slash. "~" expands to the home folder.
    param([string]$Path)
    $home2 = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    if ($Path -eq "~") { $Path = $home2 }
    elseif ($Path.StartsWith("~/") -or $Path.StartsWith("~\")) { $Path = Join-Path $home2 $Path.Substring(2) }
    return $Path.Replace("\", "/").TrimEnd("/").ToLowerInvariant()
}

function ConvertTo-AdoUrlKey {
    # host + path, lowercase, without scheme, user, or port. Works for https and ssh remotes.
    param([string]$Url)
    $u = $Url.Trim().ToLowerInvariant()
    $u = $u -replace "^[a-z+]+://", ""
    $u = $u -replace "^[^@/]+@", ""
    $u = $u -replace "^([^/:]+):\d+", '$1'
    $u = $u -replace "^([^/:]+):(?!/)", '$1/'
    return $u.TrimEnd("/")
}

function Read-AdoConfig {
    # Returns { Config, Connections (ordered name -> raw object), Names, NamesText }.
    param([string]$ConfigPath, [string]$MissingHint = "")
    if (-not (Test-Path $ConfigPath)) {
        throw "Config not found at $ConfigPath. Copy config.example.json there and fill it in.$MissingHint"
    }
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $connections = [ordered]@{}
    $connSource = Get-AdoProp $config "connections"
    if ($connSource) {
        foreach ($p in $connSource.PSObject.Properties) { $connections[$p.Name] = $p.Value }
    }
    elseif (Get-AdoProp $config "serverUrl") {
        # A flat config (serverUrl at the top) is one connection named "default".
        $connections["default"] = $config
    }
    if ($connections.Count -eq 0) { throw "config.json has no 'connections' (or 'serverUrl'). See config.example.json." }
    $names = @($connections.Keys)
    return [pscustomobject]@{
        Config      = $config
        Connections = $connections
        Names       = $names
        NamesText   = ($names -join ", ")
        Path        = $ConfigPath
    }
}

function Get-AdoConnection {
    param($Cfg, [string]$Name)
    $c = $Cfg.Connections[$Name]
    $topApi = Get-AdoProp $Cfg.Config "apiVersion"
    $topAuth = Get-AdoProp $Cfg.Config "auth"
    $topPatEnv = Get-AdoProp $Cfg.Config "patEnv"
    $conn = [pscustomobject]@{
        Name       = $Name
        ServerUrl  = (Get-AdoProp $c "serverUrl")
        Collection = (Get-AdoProp $c "collection")
        Project    = (Get-AdoProp $c "project")
        ApiVersion = $(if (Get-AdoProp $c "apiVersion") { Get-AdoProp $c "apiVersion" } elseif ($topApi) { $topApi } else { "6.0" })
        Auth       = $(if (Get-AdoProp $c "auth") { Get-AdoProp $c "auth" } elseif ($topAuth) { $topAuth } else { "pat" })
        PatEnv     = $(if (Get-AdoProp $c "patEnv") { Get-AdoProp $c "patEnv" } elseif ($topPatEnv) { $topPatEnv } else { "ADO_PAT" })
        Reason     = ""
        Base       = ""
    }
    foreach ($key in @("ServerUrl", "Collection")) {
        if (-not $conn.$key) { throw "Connection '$Name' in config.json is missing '$($key.Substring(0,1).ToLowerInvariant() + $key.Substring(1))'." }
    }
    if ($conn.ServerUrl -match "example\.local") {
        throw "Connection '$Name' still has the example serverUrl. Fill in your real ADO Server URL in $($Cfg.Path)."
    }
    $conn.Base = "$($conn.ServerUrl.TrimEnd('/'))/$($conn.Collection)"
    return $conn
}

function Find-AdoPathMapping {
    # Longest matching pattern wins. "*" matches any characters, including slashes.
    param($Cfg, [string]$Path)
    $map = Get-AdoProp $Cfg.Config "paths"
    if (-not $map) { return $null }
    $key = ConvertTo-AdoPathKey $Path
    $best = $null
    $bestLen = -1
    foreach ($p in $map.PSObject.Properties) {
        $pattern = ConvertTo-AdoPathKey $p.Name
        if (($key -like $pattern) -or ("$key/" -like $pattern) -or ($key -like "$pattern/*")) {
            if ($pattern.Length -gt $bestLen) { $best = $p; $bestLen = $pattern.Length }
        }
    }
    if ($best) {
        if (-not $Cfg.Connections.Contains([string]$best.Value)) { throw "config.json 'paths' maps '$($best.Name)' to '$($best.Value)', which is not a connection. Connections: $($Cfg.NamesText)" }
        return [pscustomobject]@{ Name = [string]$best.Value; Pattern = $best.Name }
    }
    return $null
}

function Find-AdoUrlMapping {
    # Which connection a repo or PR URL belongs to: its serverUrl + collection prefix.
    # Also returns the project and repo names when the URL has them (.../<project>/_git/<repo>...).
    param($Cfg, [string]$Url)
    if (-not $Url) { return $null }
    $urlKey = ConvertTo-AdoUrlKey ([string]$Url)
    $project = $null
    $repo = $null
    foreach ($n in $Cfg.Names) {
        $c = $Cfg.Connections[$n]
        $server = Get-AdoProp $c "serverUrl"
        $coll = Get-AdoProp $c "collection"
        if (-not $server -or -not $coll) { continue }
        $prefix = (ConvertTo-AdoUrlKey $server) + "/" + $coll.ToLowerInvariant() + "/"
        if ($urlKey.StartsWith($prefix)) {
            if (([string]$Url) -match ("(?i)/" + [regex]::Escape($coll) + "/([^/]+)/_git/([^/?#]+)")) {
                $project = [System.Uri]::UnescapeDataString($Matches[1])
                $repo = [System.Uri]::UnescapeDataString($Matches[2])
            }
            return [pscustomobject]@{ Name = $n; Url = [string]$Url; Project = $project; Repo = $repo }
        }
    }
    return [pscustomobject]@{ Name = $null; Url = [string]$Url; Project = $null; Repo = $null }
}

function Get-AdoRemoteUrl {
    param([string]$RepoPath)
    $url = $null
    try { $url = (& git -C $RepoPath remote get-url origin 2>$null) } catch { }
    if ($url) { return [string]$url }
    return $null
}

function Resolve-AdoConnection {
    # Picks the connection (order in the file header). Returns it with .Reason and .Base set.
    param($Cfg, [string]$From)
    $conn = $null
    $repoPath = $null
    $remoteNote = $null
    if ($From) {
        if ($Cfg.Connections.Contains($From)) {
            $conn = Get-AdoConnection $Cfg $From
            $conn.Reason = "named with -From"
        }
        elseif (Test-Path $From -PathType Container) {
            $repoPath = (Resolve-Path $From).Path
        }
        else {
            throw "UNKNOWN: -From '$From' is not a connection name or a folder. Connections: $($Cfg.NamesText)"
        }
    }
    if (-not $conn -and $repoPath) {
        $m = Find-AdoPathMapping $Cfg $repoPath
        if ($m) { $conn = Get-AdoConnection $Cfg $m.Name; $conn.Reason = "repo path matches '$($m.Pattern)'" }
        else {
            $r = Find-AdoUrlMapping $Cfg (Get-AdoRemoteUrl $repoPath)
            if ($r -and $r.Name) {
                $conn = Get-AdoConnection $Cfg $r.Name
                $conn.Reason = "repo remote $($r.Url)"
                if ($r.Project) { $conn.Project = $r.Project }
            }
            elseif ($r) { $remoteNote = "The remote $($r.Url) matches no connection's serverUrl + collection." }
        }
    }
    if (-not $conn) {
        $m = Find-AdoPathMapping $Cfg (Get-Location).Path
        if ($m) { $conn = Get-AdoConnection $Cfg $m.Name; $conn.Reason = "current folder matches '$($m.Pattern)'" }
    }
    if (-not $conn) {
        $def = Get-AdoProp $Cfg.Config "default"
        if ($def) {
            if (-not $Cfg.Connections.Contains([string]$def)) { throw "config.json 'default' is '$def', which is not a connection. Connections: $($Cfg.NamesText)" }
            $conn = Get-AdoConnection $Cfg ([string]$def); $conn.Reason = "default connection"
        }
        elseif ($Cfg.Names.Count -eq 1) {
            $conn = Get-AdoConnection $Cfg $Cfg.Names[0]; $conn.Reason = "only connection"
        }
    }
    if (-not $conn) {
        $msg = "AMBIGUOUS: could not tell which ADO connection to use. Rerun with -From <connection name or repo folder>. Connections: $($Cfg.NamesText)"
        if ($remoteNote) { $msg += " ($remoteNote)" }
        throw $msg
    }
    return $conn
}

function Write-AdoConnectionInfo {
    param($Conn, [string]$ProjectNote = "(not set)")
    Write-Output "Connection : $($Conn.Name) ($($Conn.Reason))"
    Write-Output "Base URL   : $($Conn.Base)"
    Write-Output "Project    : $(if ($Conn.Project) { $Conn.Project } else { $ProjectNote })"
    Write-Output "API version: $($Conn.ApiVersion)"
    if ($Conn.Auth -eq "windows") { Write-Output "Auth       : windows (your Windows login)" }
    else {
        $isSet = if ([Environment]::GetEnvironmentVariable($Conn.PatEnv)) { "set" } else { "NOT SET" }
        Write-Output "Auth       : pat from $($Conn.PatEnv) ($isSet)"
    }
}

function New-AdoRequest {
    # A splat for Invoke-RestMethod with auth set. Add .Uri before calling.
    param($Conn, [string]$MissingPatHint = "")
    $request = @{ Method = "Get"; ContentType = "application/json" }
    if ($Conn.Auth -eq "windows") {
        $request.UseDefaultCredentials = $true
    }
    else {
        $pat = [Environment]::GetEnvironmentVariable($Conn.PatEnv)
        if (-not $pat) { throw "$($Conn.PatEnv) environment variable is not set (connection '$($Conn.Name)').$MissingPatHint" }
        $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":" + $pat))
        $request.Headers = @{ Authorization = "Basic $basic" }
    }
    # Windows PowerShell 5.1 may default to old TLS versions.
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    return $request
}

function ConvertFrom-AdoHtml {
    param([string]$Html)
    if (-not $Html) { return "" }
    $t = $Html
    $t = $t -replace "(?i)<br\s*/?>", "`n"
    $t = $t -replace "(?i)</(p|div|h[1-6]|tr)>", "`n"
    $t = $t -replace "(?i)<li[^>]*>", "`n- "
    $t = $t -replace "(?i)</(td|th)>", " | "
    $t = $t -replace "<[^>]+>", ""
    $t = [System.Net.WebUtility]::HtmlDecode($t)
    $t = $t -replace "[ \t]+\n", "`n"
    $t = $t -replace "\n{3,}", "`n`n"
    return $t.Trim()
}

function Write-AdoUtf8 {
    param([string]$Path, [string]$Content)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}
