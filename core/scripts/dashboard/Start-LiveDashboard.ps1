<#
.SYNOPSIS
    Starts the live dashboard: the /dashboard page, kept up to date, with buttons that
    run pipeline commands in opencode.

.DESCRIPTION
    Run it from your workspace root (the folder that holds .work) and keep the window open.
    Ctrl+C stops it.

    What it does:
      - Connects to opencode. opencode 2.x: its background service (started if needed), shared
        with your TUI. opencode 1.x: "opencode serve" on port 4096 (started if needed).
      - Serves the dashboard on http://127.0.0.1:<Port>/ (this machine only) and opens it.
      - Rebuilds the page data when .work changes, and re-reads git every 20 seconds.
      - Run buttons send the next command to opencode. Each work item gets its own session;
        /do-task and /check-docs get a fresh one, as the pipeline requires.
      - Shows each item's agent: working or done, what it is doing, its last reply, and any
        permission prompt or question waiting for you. You can answer and reply from the page.
      - Checks for eng-agents updates every few hours (update.ps1 -Check) and shows "Update
        available" in the header. Updating from the page restarts the dashboard in this window.
      - Optional shell: a site listed in config.json ("dashboard": { "shellOrigins": [...] }) can show
        this dashboard inside its own page and read where each work item stands. The EM Hub does this.
      - Autopilot: after you approve the plan (or bug analysis), runs tasks, each task in a new
        session, review, and PR text, and stops only when it needs you. Never pushes.

    To use the terminal on the same sessions:
      opencode 2.x  just run opencode (it uses the same background service)
      opencode 1.x  opencode attach http://127.0.0.1:4096 instead of plain opencode

    Writes only to .work\_dashboard\ (session links, autopilot state, the opencode log), except
    Abandon and Remove, which delete that item's .work folder after you confirm. It never calls
    ADO. It pushes only when you click Push on a PR card. Commands it runs follow the same
    permission rules as in the TUI.

    Needs Node 18 or newer (node on PATH).

    -Detach starts it in its own minimized window and returns as soon as it is up, or just opens
    it if it is already running. /dashboard in opencode uses this.

.EXAMPLE
    .\Start-LiveDashboard.ps1

.EXAMPLE
    .\Start-LiveDashboard.ps1 -Detach

.EXAMPLE
    .\Start-LiveDashboard.ps1 -Workspace C:\src\work -Port 4310
#>
[CmdletBinding()]
param(
    # The folder that holds .work. Default: the current folder.
    [string]$Workspace = (Get-Location).Path,

    # Port for the dashboard page.
    [int]$Port = 4300,

    # Use this opencode server instead of finding one. Default: opencode 2.x uses its
    # background service; opencode 1.x uses (and starts) http://127.0.0.1:4096.
    [string]$OpencodeUrl,

    # ADO config, only used to build work item links.
    [string]$ConfigPath = (Join-Path $(if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }) ".config/eng-agents/config.json"),

    # Do not open the browser.
    [switch]$NoOpen,

    # Do not start opencode if it is not running.
    [switch]$NoOpencode,

    # Do not check for eng-agents updates.
    [switch]$NoUpdateCheck,

    # Sites allowed to embed the dashboard and read item stages (a shell such as the EM Hub).
    # Usually set once in config.json instead: "dashboard": { "shellOrigins": ["https://..."] }.
    [string[]]$ShellOrigin,

    # Start it in its own minimized window and return once it answers. If it is already running
    # for this workspace, just open it.
    [switch]$Detach
)

$ErrorActionPreference = "Stop"

$server = Join-Path $PSScriptRoot "live-server.mjs"
if (-not (Test-Path -LiteralPath $server)) { throw "Missing $server. Re-run install.ps1." }

$ws = (Resolve-Path -LiteralPath $Workspace -ErrorAction SilentlyContinue)
if (-not $ws) { throw "Folder not found: $Workspace" }
$ws = $ws.Path
if (-not (Test-Path -LiteralPath (Join-Path $ws ".work") -PathType Container)) {
    throw "No .work folder in $ws. Run this from your workspace root, or pass -Workspace <path>."
}

$node = Get-Command node -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $node) { throw "Node is not on PATH. Install Node 18 or newer (https://nodejs.org), then open a new terminal." }
$ver = (& $node.Source --version) -replace '^v', ''
if ([int]($ver.Split('.')[0]) -lt 18) { throw "Node $ver is too old. The live dashboard needs Node 18 or newer." }

# Run New-Dashboard.ps1 with the same PowerShell that is running this script.
$ps = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

if ($Detach) {
    $url = "http://127.0.0.1:$Port/"
    function Get-Ping {
        try { return Invoke-RestMethod -Uri "${url}api/ping" -TimeoutSec 2 -ErrorAction Stop } catch { return $null }
    }
    function Open-Page {
        if ($NoOpen) { return }
        try {
            if ($PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows) { Start-Process $url }
            elseif ($IsMacOS) { & open $url }
            elseif (Get-Command xdg-open -ErrorAction SilentlyContinue) { & xdg-open $url 2>$null | Out-Null }
        }
        catch { }
    }
    $same = { param($p) $p -and $p.app -eq "eng-agents-dashboard" -and ([string]$p.workspace).TrimEnd('\', '/') -eq $ws.TrimEnd('\', '/') }
    $ping = Get-Ping
    if ($ping) {
        if (-not (& $same $ping)) { throw "Port $Port is in use$(if ($ping.workspace) { " by the dashboard for $($ping.workspace)" }). Pass -Port <n>." }
        Open-Page
        Write-Output "Already running: $url"
        exit 0
    }

    # The same command without -Detach, in its own window. Closing that window stops the dashboard.
    $q = { param($v) "`"$($v -replace '"', '\"')`"" }
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (& $q $PSCommandPath), "-Workspace", (& $q $ws), "-Port", $Port, "-ConfigPath", (& $q $ConfigPath))
    if ($OpencodeUrl) { $argList += @("-OpencodeUrl", (& $q $OpencodeUrl)) }
    if ($NoOpen) { $argList += "-NoOpen" }
    if ($NoOpencode) { $argList += "-NoOpencode" }
    if ($NoUpdateCheck) { $argList += "-NoUpdateCheck" }
    foreach ($o in @($ShellOrigin | Where-Object { $_ })) { $argList += @("-ShellOrigin", (& $q $o)) }
    $logFile = Join-Path $ws ".work/_dashboard/live.log"
    if ($PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows) {
        Start-Process -FilePath $ps -ArgumentList $argList -WorkingDirectory $ws -WindowStyle Minimized | Out-Null
    }
    else {
        # macOS and Linux: no window to put it in, so it runs in the background and logs to a file.
        # nohup and a shell redirect keep it running after this script and its terminal exit.
        New-Item -ItemType Directory -Force -Path (Split-Path $logFile) | Out-Null
        $sq = { param($v) "'" + ([string]$v -replace "'", "'\''") + "'" }
        $plain = @($argList | ForEach-Object { ([string]$_).Trim('"') })
        $line = "cd " + (& $sq $ws) + " && nohup " + ((@($ps) + $plain | ForEach-Object { & $sq $_ }) -join " ") + " > " + (& $sq $logFile) + " 2>&1 &"
        & /bin/sh -c $line
    }
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 500
        $ping = Get-Ping
        if (& $same $ping) {
            Write-Output "Live dashboard: $url"
            Write-Output $(if ($PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows) { "It runs in its own minimized window. Close that window to stop it." } else { "It runs in the background. Log: $logFile" })
            exit 0
        }
    }
    throw "The live dashboard did not start within 30 seconds. $(if ($PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows) { 'Look at its window for the error.' } else { "See $logFile" })"
}

$nodeArgs = @($server, "--workspace", $ws, "--port", $Port, "--ps", $ps, "--config", $ConfigPath)
if ($OpencodeUrl) { $nodeArgs += @("--opencode", $OpencodeUrl) }
if ($NoOpen) { $nodeArgs += "--no-open" }
if ($NoOpencode) { $nodeArgs += "--no-start-opencode" }
if ($NoUpdateCheck) { $nodeArgs += "--no-update-check" }
foreach ($o in @($ShellOrigin | Where-Object { $_ })) { $nodeArgs += @("--shell-origin", $o) }

# The server exits with 75 after an update (or the Restart button) so it can start again on the new
# code. The open page reloads by itself, so no new browser tab on a restart.
$env:ENG_DASHBOARD_SUPERVISED = "1"
while ($true) {
    & $node.Source @nodeArgs
    $code = $LASTEXITCODE
    if ($code -ne 75) { break }
    Write-Host ""
    Write-Host "Restarting the live dashboard..."
    if ($nodeArgs -notcontains "--no-open") { $nodeArgs += "--no-open" }
}
exit $code
