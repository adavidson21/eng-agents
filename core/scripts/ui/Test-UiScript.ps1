<#
.SYNOPSIS
    Self-test for Test-Ui.ps1, Start-UiApp.ps1 and Stop-UiApp.ps1: the paths that need no browser (reading the UI checks table, skipping when
    there is no table, no URL or no changed UI file). check-ui.mjs has its own tests (node --test "core/scripts/ui/test/*.test.mjs").
#>
$ErrorActionPreference = "Stop"
$script = Join-Path $PSScriptRoot "Test-Ui.ps1"
$fails = 0
function Check([string]$Name, [bool]$Ok, [string]$Got) {
    if ($Ok) { Write-Output "ok   $Name" } else { Write-Output "FAIL $Name (got: $Got)"; $script:fails++ }
}
function Last($Lines) { return "$(@($Lines)[-1])" }

$root = Join-Path ([IO.Path]::GetTempPath()) ("ui-test-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Path $root | Out-Null
try {
    $repo = Join-Path $root "repo"
    New-Item -ItemType Directory -Path (Join-Path $repo "src") -Force | Out-Null
    & git -C $repo init -q 2>$null
    Set-Content -LiteralPath (Join-Path $repo "src/a.html") -Value "a"
    Set-Content -LiteralPath (Join-Path $repo "README.md") -Value "r"
    & git -C $repo add -A
    & git -C $repo -c user.email=t@t -c user.name=t commit -qm init
    & git -C $repo branch base
    Add-Content -LiteralPath (Join-Path $repo "README.md") -Value "more"
    & git -C $repo -c user.email=t@t -c user.name=t commit -qam docs

    $wf = Join-Path $root "work"
    New-Item -ItemType Directory -Path $wf | Out-Null
    $guide = Join-Path $repo "AGENTS.md"

    Set-Content -LiteralPath $guide -Value "# Guide`n`n## Commands`n"
    $r = & $script -WorkFolder $wf -Repo $repo -Guide $guide -Name after
    Check "no table: skipped" ((Last $r) -match '^UI: SKIPPED the repo guide has no UI checks table') (Last $r)

    Set-Content -LiteralPath $guide -Value "# Guide`n`n## UI checks`n`n| Field | Value |`n|---|---|`n| Start | <command> |`n| URL | <http://localhost:port> |`n`n## Other`n| URL | http://wrong |`n"
    $r = & $script -WorkFolder $wf -Repo $repo -Guide $guide -Name after
    Check "template placeholders and other sections are not read" ((Last $r) -match 'has no UI checks table') (Last $r)

    Set-Content -LiteralPath $guide -Value "# Guide`n`n## UI checks`n`n| Field | Value |`n|---|---|`n| Start | ``node server.js`` |`n| URL | ``http://127.0.0.1:9`` |`n| UI files | ``src/**``, ``*.scss`` |`n"
    $r = & $script -WorkFolder $wf -Repo $repo -Guide $guide -Name after -Base base
    Check "only non-UI files changed: skipped" ((Last $r) -eq 'UI: SKIPPED no UI files changed') (Last $r)

    Add-Content -LiteralPath (Join-Path $repo "src/a.html") -Value "b"
    & git -C $repo -c user.email=t@t -c user.name=t commit -qam ui
    $r = & $script -WorkFolder $wf -Repo $repo -Guide $guide -Name after -Base base -TimeoutSeconds 10
    Check "UI file changed: the check runs and ends with a UI line" ((Last $r) -match '^UI: (PASS|FAIL|SKIPPED) ' -and (Last $r) -ne 'UI: SKIPPED no UI files changed') (Last $r)

    $r = & $script -WorkFolder $wf -Repo (Join-Path $root "missing") -Guide $guide -Name after
    Check "missing repo folder: skipped" ((Last $r) -match '^UI: SKIPPED no repo folder') (Last $r)

    # Per-task checks (Core 4.15.0): only when the uncommitted changes touch UI files.
    $r = & $script -WorkFolder $wf -Repo $repo -Guide $guide -Name task-1 -Quick -Uncommitted
    Check "per task, nothing uncommitted: skipped" ((Last $r) -eq 'UI: SKIPPED no UI files changed') (Last $r)
    Add-Content -LiteralPath (Join-Path $repo "README.md") -Value "docs only"
    $r = & $script -WorkFolder $wf -Repo $repo -Guide $guide -Name task-1 -Quick -Uncommitted
    Check "per task, only a non-UI file changed: skipped" ((Last $r) -eq 'UI: SKIPPED no UI files changed') (Last $r)
    Set-Content -LiteralPath (Join-Path $repo "src/b.html") -Value "new page"
    $r = & $script -WorkFolder $wf -Repo $repo -Guide $guide -Name task-1 -Quick -Uncommitted -Pages "/b" -TimeoutSeconds 10
    Check "per task, a new UI file: the check runs" ((Last $r) -match '^UI: (PASS|FAIL|SKIPPED) ' -and (Last $r) -ne 'UI: SKIPPED no UI files changed') (Last $r)

    # The build's warm app: Start-UiApp.ps1 starts it with a free {port} and reuses it; Stop-UiApp.ps1 ends it.
    $start = Join-Path $PSScriptRoot "Start-UiApp.ps1"
    $stop = Join-Path $PSScriptRoot "Stop-UiApp.ps1"
    Set-Content -LiteralPath (Join-Path $repo "server.js") -Value 'require("http").createServer((q, s) => s.end("hi")).listen(Number(process.argv[2]), "127.0.0.1");'
    Set-Content -LiteralPath $guide -Value "# Guide`n`n## UI checks`n`n| Field | Value |`n|---|---|`n| Start | ``node server.js {port}`` |`n| URL | ``http://127.0.0.1:{port}`` |`n| UI files | ``src/**`` |`n"
    $r = & $stop -WorkFolder $wf
    Check "stop with no app: none" ((Last $r) -eq 'APP: NONE') (Last $r)
    $r = & $start -WorkFolder $wf -Repo $repo -Guide $guide -TimeoutSeconds 20
    Check "start: running on a free port" ((Last $r) -match '^APP: RUNNING http://127\.0\.0\.1:\d+$') (Last $r)
    $first = Last $r
    $r = & $start -WorkFolder $wf -Repo $repo -Guide $guide -TimeoutSeconds 20
    Check "start again: the same app" ((Last $r) -eq $first) (Last $r)
    Check "app.json records it" (Test-Path -LiteralPath (Join-Path $wf "ui/app.json")) "no app.json"
    $r = & $stop -WorkFolder $wf
    Check "stop: stopped" ((Last $r) -eq 'APP: STOPPED') (Last $r)
    Check "app.json is gone" (-not (Test-Path -LiteralPath (Join-Path $wf "ui/app.json"))) "app.json still there"
    Set-Content -LiteralPath $guide -Value "# Guide`n"
    $r = & $start -WorkFolder $wf -Repo $repo -Guide $guide
    Check "start with no table: skipped" ((Last $r) -match '^APP: SKIPPED the repo guide has no UI checks table') (Last $r)
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
if ($fails) { Write-Output "$fails UI script check(s) failed."; exit 1 }
Write-Output "All UI script checks passed."
