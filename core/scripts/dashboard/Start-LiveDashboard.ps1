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
      - Autopilot: after you approve the plan (or bug analysis), runs tasks, each task in a new
        session, review, and PR text, and stops only when it needs you. Never pushes.

    To use the terminal on the same sessions:
      opencode 2.x  just run opencode (it uses the same background service)
      opencode 1.x  opencode attach http://127.0.0.1:4096 instead of plain opencode

    Read-only apart from .work\_dashboard\ (session links and the opencode log). It never calls
    ADO and never pushes. Commands it runs follow the same permission rules as in the TUI.

    Needs Node 18 or newer (node on PATH).

.EXAMPLE
    .\Start-LiveDashboard.ps1

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
    [switch]$NoOpencode
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

$nodeArgs = @($server, "--workspace", $ws, "--port", $Port, "--ps", $ps, "--config", $ConfigPath)
if ($OpencodeUrl) { $nodeArgs += @("--opencode", $OpencodeUrl) }
if ($NoOpen) { $nodeArgs += "--no-open" }
if ($NoOpencode) { $nodeArgs += "--no-start-opencode" }

& $node.Source @nodeArgs
exit $LASTEXITCODE
