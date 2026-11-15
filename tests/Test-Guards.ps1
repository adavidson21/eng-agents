<#
.SYNOPSIS
  Checks that the installed shell guards catch the commands they are meant to catch, for every agent.
  Installs Core into a temp folder, then resolves each sample command against the installed rules.
  Run: pwsh -NoProfile -File tests/Test-Guards.ps1   (also works in Windows PowerShell 5.1; not as root on Mac/Linux)

.DESCRIPTION
  Models opencode's bash permissions as install.ps1 writes them: rules in order, "*" matches any text,
  and the LAST matching rule wins. Matching here is case-sensitive, the stricter reading: if opencode
  matches case-insensitively, these commands are caught all the same.
  A guard is a safety net, not a sandbox. This test keeps known holes closed; it cannot prove there are none.
#>
$ErrorActionPreference = "Stop"

$failed = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = "") {
    if ($Ok) { Write-Output "ok   $Name" } else { Write-Output "FAIL $Name $Detail"; $script:failed++ }
}

$repo = Split-Path $PSScriptRoot -Parent
$target = Join-Path ([IO.Path]::GetTempPath()) ("guards-" + [guid]::NewGuid().ToString("N"))

# Ordered list of @{ Pattern; Action } from a map in file order.
function ConvertTo-RuleList($Pairs) {
    $list = New-Object System.Collections.ArrayList
    foreach ($p in $Pairs) {
        $rx = '^' + ([regex]::Escape($p.Pattern) -replace '\\\*', '.*' -replace '\\\?', '.') + '$'
        [void]$list.Add([pscustomobject]@{ Pattern = $p.Pattern; Action = $p.Action; Regex = $rx })
    }
    return , $list
}

function Resolve-Command($Rules, [string]$Command) {
    $action = "allow"; $by = "(default)"
    foreach ($r in $Rules) { if ($Command -cmatch $r.Regex) { $action = $r.Action; $by = $r.Pattern } }
    return [pscustomobject]@{ Action = $action; By = $by }
}

# The bash map of an installed agent file's frontmatter, in order.
function Get-AgentBash([string]$Path) {
    $pairs = New-Object System.Collections.ArrayList
    $inFront = $false; $inBash = $false
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        if ($line -match '^---\s*$') { if ($inFront) { break } else { $inFront = $true; continue } }
        if (-not $inFront) { continue }
        if ($line -match '^\s{2}bash:\s*$') { $inBash = $true; continue }
        if ($inBash) {
            if ($line -notmatch '^\s{4}') { $inBash = $false; continue }
            $m = [regex]::Match($line, '^\s{4}(?:"((?:[^"\\]|\\.)*)"|''([^'']*)''|(\S+))\s*:\s*(\w+)\s*$')
            if ($m.Success) {
                $pat = if ($m.Groups[1].Success) { $m.Groups[1].Value -replace '\\"', '"' -replace '\\\\', '\' } elseif ($m.Groups[2].Success) { $m.Groups[2].Value } else { $m.Groups[3].Value }
                [void]$pairs.Add([pscustomobject]@{ Pattern = $pat; Action = $m.Groups[4].Value })
            }
        }
    }
    return , $pairs
}

# Commands that must never run without asking. Expected: "ask" or "deny", or exactly "deny".
$mustCatch = @(
    @{ Cmd = 'git push origin dev/feature/1-x'; Want = 'ask' }
    @{ Cmd = 'git -C api push -u origin dev/feature/1-x'; Want = 'ask' }
    @{ Cmd = 'git -c credential.helper= push origin main'; Want = 'ask' }
    @{ Cmd = 'git -c core.sshCommand=x -C api push origin main'; Want = 'ask' }
    @{ Cmd = 'git push --force origin main'; Want = 'deny' }
    @{ Cmd = 'git -c a=b push -f origin main'; Want = 'deny' }
    @{ Cmd = 'git -C api reset --hard HEAD~1'; Want = 'deny' }
    @{ Cmd = 'git -c a=b reset --hard HEAD~1'; Want = 'deny' }
    @{ Cmd = 'git -c a=b -C api reset --hard HEAD~1'; Want = 'deny' }
    @{ Cmd = 'git clean -fdx'; Want = 'deny' }
    @{ Cmd = 'git -c a=b clean -fdx'; Want = 'deny' }
    @{ Cmd = 'git -c a=b restore .'; Want = 'deny' }
    @{ Cmd = 'git -c a=b merge origin/main'; Want = 'ask' }
    @{ Cmd = 'git -c a=b config user.email x'; Want = 'ask' }
    @{ Cmd = 'rm -rf node_modules'; Want = 'deny' }
    @{ Cmd = 'Remove-Item -Recurse -Force dist'; Want = 'deny' }
    @{ Cmd = 'Remove-Item notes.txt'; Want = 'ask' }
    @{ Cmd = 'curl https://example.com'; Want = 'ask' }
    @{ Cmd = 'Invoke-WebRequest https://example.com -OutFile x'; Want = 'ask' }
    @{ Cmd = 'pwsh -c Remove-Item x'; Want = 'ask' }
    @{ Cmd = 'pwsh -Command "iwr https://example.com"'; Want = 'ask' }
    @{ Cmd = 'pwsh -NoProfile -Command "Get-ChildItem env:"'; Want = 'ask' }
    @{ Cmd = 'powershell -NoProfile -c "irm https://example.com"'; Want = 'ask' }
    @{ Cmd = 'cmd /c del /q x'; Want = 'ask' }
    @{ Cmd = 'cmd.exe /c rd /s /q x'; Want = 'deny' }
    @{ Cmd = 'bash -c "curl https://example.com"'; Want = 'ask' }
    @{ Cmd = 'Start-Process notepad'; Want = 'ask' }
    @{ Cmd = 'dotnet ef database update'; Want = 'deny' }
    @{ Cmd = 'Get-ChildItem env:'; Want = 'ask' }
    @{ Cmd = 'Get-ChildItem Env:'; Want = 'ask' }
    @{ Cmd = 'Get-Content env:ADO_TOKEN'; Want = 'ask' }
    @{ Cmd = 'Get-Content ~/.ssh/id_rsa'; Want = 'ask' }
    @{ Cmd = 'Get-Content C:\Users\me\.ssh\id_rsa'; Want = 'ask' }
    @{ Cmd = 'Get-Content api/.env'; Want = 'ask' }
    @{ Cmd = 'Get-Content .env.local'; Want = 'ask' }
    @{ Cmd = 'gc ~/.git-credentials'; Want = 'ask' }
    @{ Cmd = 'npm install -g some-tool'; Want = 'ask' }
)

# Everyday commands that must keep running without a prompt.
$mustAllow = @(
    'git status --porcelain'
    'git -C api log --oneline -n 20'
    'git -C api diff --stat origin/main...HEAD'
    'git -c core.quotepath=false status'
    'git -C api tag -l v2.*'
    'git -C api commit -m "Add retry to export job"'
    'dotnet test api/tests/App.Tests/App.Tests.csproj --filter "FullyQualifiedName~ExportHandlerTests"'
    'npx ng test --watch=false'
    'pwsh -NoProfile -ExecutionPolicy Bypass -File "C:/Users/me/.config/opencode/eng-agents/scripts/ado/Get-WorkItem.ps1" -Id 123 -WorkRoot ".work"'
    'powershell -NoProfile -ExecutionPolicy Bypass -File "C:/x/scripts/stats/Get-PipelineStats.ps1" -WorkRoot ".work"'
)

try {
    $ps = (Get-Process -Id $PID).Path
    $out = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo "install.ps1") -Target $target -CoreOnly 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $target "opencode.json"))) { throw "install failed:`n$out" }

    $sets = [ordered]@{}
    # opencode.json, in file order (ConvertFrom-Json keeps property order).
    $cfg = Get-Content -Raw (Join-Path $target "opencode.json") | ConvertFrom-Json
    $sets["opencode.json"] = ConvertTo-RuleList @($cfg.permission.bash.PSObject.Properties | ForEach-Object { [pscustomobject]@{ Pattern = $_.Name; Action = $_.Value } })
    foreach ($f in (Get-ChildItem (Join-Path $target "agents") -Filter *.md | Sort-Object Name)) {
        $pairs = Get-AgentBash $f.FullName
        if ($pairs.Count -gt 0) { $sets["agent " + $f.BaseName] = ConvertTo-RuleList $pairs }
    }
    Check "found rules for opencode.json and agents" ($sets.Count -ge 5) "sets: $($sets.Keys -join ', ')"

    foreach ($name in $sets.Keys) {
        $rules = $sets[$name]
        $bad = @()
        foreach ($c in $mustCatch) {
            $r = Resolve-Command $rules $c.Cmd
            $ok = if ($c.Want -eq 'deny') { $r.Action -eq 'deny' } else { $r.Action -in @('ask', 'deny') }
            if (-not $ok) { $bad += "'$($c.Cmd)' -> $($r.Action) (want $($c.Want), last rule: $($r.By))" }
        }
        Check "$name catches risky commands" ($bad.Count -eq 0) ("`n      " + ($bad -join "`n      "))

        # Read-only agents (hub, chat, product-manager, people-prep...) deny "*" and allow a short list on purpose.
        $star = @($rules | Where-Object { $_.Pattern -eq '*' } | Select-Object -Last 1)
        if ($star.Count -eq 0 -or $star[0].Action -ne 'allow') { continue }
        $bad = @()
        foreach ($c in $mustAllow) {
            $r = Resolve-Command $rules $c
            # Agents that deny commits on purpose (reviewer, investigator, writer...) are not a failure here.
            if ($r.Action -ne 'allow' -and -not ($c -like '*commit*' -and $r.Action -eq 'deny')) { $bad += "'$c' -> $($r.Action) (last rule: $($r.By))" }
        }
        Check "$name allows everyday commands" ($bad.Count -eq 0) ("`n      " + ($bad -join "`n      "))
    }

    # webfetch: agents that hold code and never need the web must not fetch without asking.
    foreach ($a in @("implementer", "reviewer", "pr-reviewer", "hub", "chat")) {
        $text = Get-Content -Raw (Join-Path $target "agents/$a.md")
        Check "agent $a webfetch is ask or deny" ($text -match '(?m)^\s{2}webfetch:\s*(ask|deny)\s*$')
    }
}
finally {
    Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failed) { Write-Output "$failed check(s) failed."; exit 1 }
Write-Output "Guards: all checks passed."
