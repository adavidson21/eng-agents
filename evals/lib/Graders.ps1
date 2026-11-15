<#
.SYNOPSIS
    Deterministic graders for the eval cases. Dot-source after EvalLib.ps1.

.DESCRIPTION
    Each grader takes the workspace from New-EvalWorkspace (-Ws) and returns a list of checks:
    [pscustomobject]@{ Check = "<name>"; Pass = $true/$false; Detail = "<why it failed>" }.
    A run passes when every check passes. -NoExec skips checks that run dotnet (used by Test-Graders.ps1).
    Graders only read files and git state; they never change the workspace, except the do-task grader,
    which adds a hidden acceptance test, runs it and removes it again.
#>

. (Join-Path $script:RepoRoot "core/scripts/work/DraftHash.ps1")

$script:AllowedCategories = @("architecture", "consistency", "correctness", "efcore", "security", "tests", "angular", "playwright", "leftovers", "spec", "scope", "checklist", "tdd")

function New-Checks { return , (New-Object System.Collections.ArrayList) }
function Add-Check($List, [string]$Name, [bool]$Pass, [string]$Detail = "") {
    [void]$List.Add([pscustomobject]@{ Check = $Name; Pass = $Pass; Detail = $(if ($Pass) { "" } else { $Detail }) })
}

function Read-WorkFile($Ws, [string]$Name) {
    $p = Join-Path $Ws.Work $Name
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    return [IO.File]::ReadAllText($p)
}

function Get-MdSection([string]$Text, [string]$Heading) {
    if (-not $Text) { return "" }
    $m = [regex]::Match($Text, '(?ms)^##\s+' + [regex]::Escape($Heading) + '[^\r\n]*\r?$(.*?)(?=^##\s|\z)')
    if ($m.Success) { return $m.Groups[1].Value } else { return "" }
}

# The last progress.md entry for a command, as text, or $null.
function Get-LastEntry([string]$Progress, [string]$Command) {
    if (-not $Progress) { return $null }
    $parts = [regex]::Split($Progress, '(?m)^(?=##\s+\d{4}-\d{2}-\d{2})')
    $hit = $null
    foreach ($p in $parts) { if ($p -match ('^##\s+\d{4}-\d{2}-\d{2}[^|]*\|\s*`?/' + [regex]::Escape($Command) + '\b')) { $hit = $p } }
    return $hit
}

function Get-StatValue([string]$Entry, [string]$Key) {
    if (-not $Entry) { return $null }
    $m = [regex]::Match($Entry, '(?mi)^\s*-\s*Stats\s*:.*?\b' + [regex]::Escape($Key) + '=([^\s,;`]+)')
    if ($m.Success) { return $m.Groups[1].Value } else { return $null }
}

function Get-Tasks([string]$Text) {
    $list = New-Object System.Collections.ArrayList
    if (-not $Text) { return , $list }
    $blocks = [regex]::Split($Text, '(?m)^(?=##\s*\[[ xX]\]\s*Task\s+\d+)')
    foreach ($b in $blocks) {
        $h = [regex]::Match($b, '^##\s*\[([ xX])\]\s*Task\s+(\d+)\s*:\s*(.+)')
        if (-not $h.Success) { continue }
        $body = ($b -split '(?m)^---\s*$')[0]
        $files = @([regex]::Matches(([regex]::Match($body, '(?ms)^\s*-\s*Files:\s*\r?\n(.*?)(?=^\s*-\s*[A-Z][\w ]+:|\z)').Groups[1].Value), '`([^`]+)`') | ForEach-Object { $_.Groups[1].Value })
        $field = { param($n) $m = [regex]::Match($body, '(?mi)^\s*-\s*' + $n + ':\s*(.+)$'); if ($m.Success) { $m.Groups[1].Value.Trim() } else { $null } }
        [void]$list.Add([pscustomobject]@{
            N = [int]$h.Groups[2].Value; Done = ($h.Groups[1].Value -ne ' '); Title = $h.Groups[3].Value.Trim()
            Repo = (& $field 'Repo'); Files = $files; Human = (& $field 'Human interface'); Verify = (& $field 'Verify'); DoneWhen = (& $field 'Done when')
        })
    }
    return , $list
}

# Backticked paths that look like repo files (sample-api/...ext).
function Get-CitedPaths([string]$Text) {
    return @([regex]::Matches($Text, '`(sample-api/[^`\s:]+\.[A-Za-z]+)(?::\d+)?`') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
}

function Test-RepoUntouched($Ws, $Checks) {
    $head = Invoke-EvalGit $Ws.Repo @("rev-parse", "HEAD")
    $status = Invoke-EvalGit $Ws.Repo @("status", "--porcelain")
    Add-Check $Checks "no commits or code changes" (($head -eq $Ws.Base) -and -not $status) "HEAD moved or files changed: $status"
}

function Test-GateFile($Ws, $Checks, [string]$Name) {
    $t = Read-WorkFile $Ws $Name
    Add-Check $Checks "$Name exists" ($null -ne $t)
    if ($null -eq $t) { return $null }
    Add-Check $Checks "$Name stays DRAFT" ($t -match '(?m)^\s*Status:\s*DRAFT\s*$') "Status line is not DRAFT"
    $stored = Get-StoredDraftHash -Text $t
    Add-Check $Checks "$Name has a matching Draft-hash" ($stored -and ((Get-DraftHash -Text $t) -eq $stored)) "missing Draft-hash, or the file changed after stamping"
    return $t
}

# ------------------------------------------------------------------ graders

function Test-SpecBasic($Ws, [switch]$NoExec) {
    $c = New-Checks
    $t = Test-GateFile $Ws $c "spec.md"
    if ($t) {
        $acs = @([regex]::Matches($t, '(?m)^\s*-\s*\*\*AC-\d+:\*\*\s*(.+)$') | ForEach-Object { $_.Groups[1].Value })
        Add-Check $c "2 or more acceptance criteria" ($acs.Count -ge 2) "found $($acs.Count)"
        $bad = @($acs | Where-Object { $_ -notmatch '(?i)\bgiven\b' -or $_ -notmatch '(?i)\bwhen\b' -or $_ -notmatch '(?i)\bthen\b' })
        Add-Check $c "every AC is Given / when / then" ($acs.Count -gt 0 -and $bad.Count -eq 0) "not in Given/When/Then: $($bad -join ' | ')"
        Add-Check $c "an AC covers the 10-item threshold" (@($acs | Where-Object { $_ -match '\b10\b|ten' }).Count -ge 1)
        Add-Check $c "an AC covers smaller orders" (@($acs | Where-Object { $_ -match '(?i)fewer|less than|below|under|\b9\b' }).Count -ge 1)
        $missing = @(Get-CitedPaths $t | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Ws.Root $_)) })
        Add-Check $c "every cited path exists" ($missing.Count -eq 0) "missing: $($missing -join ', ')"
    }
    $e = Get-LastEntry (Read-WorkFile $Ws "progress.md") "spec"
    Add-Check $c "progress.md has a /spec entry" ($null -ne $e)
    Add-Check $c "auto mode asked no questions (questions=0)" ((Get-StatValue $e "questions") -eq "0") "questions=$(Get-StatValue $e 'questions')"
    Test-RepoUntouched $Ws $c
    return $c
}

function Test-PlanPaths($Ws, [switch]$NoExec) {
    $c = New-Checks
    $t = Test-GateFile $Ws $c "plan.md"
    if ($t) {
        $pm = [regex]::Match($t, '(?mi)^\s*Pattern to follow:\s*`([^`]+)`')
        Add-Check $c "a pattern to follow is named" $pm.Success
        if ($pm.Success) { Add-Check $c "the pattern file exists" (Test-Path -LiteralPath (Join-Path $Ws.Root ($pm.Groups[1].Value -replace ':\d+$', ''))) $pm.Groups[1].Value }
        $bad = @()
        foreach ($row in [regex]::Matches($t, '(?m)^\|\s*`(sample-api/[^`]+)`\s*\|\s*([^|]*)\|')) {
            $isNew = $row.Groups[2].Value -match '(?i)\bnew\b'
            if (-not $isNew -and -not (Test-Path -LiteralPath (Join-Path $Ws.Root $row.Groups[1].Value))) { $bad += $row.Groups[1].Value }
        }
        Add-Check $c "every changed file in the table exists" ($bad.Count -eq 0) "missing: $($bad -join ', ')"
        $tp = Get-MdSection $t "Test plan"
        $unc = @("AC-1", "AC-2", "AC-3" | Where-Object { $tp -notmatch [regex]::Escape($_) })
        Add-Check $c "the test plan covers every AC" ($unc.Count -eq 0) "not covered: $($unc -join ', ')"
        Add-Check $c "threshold and rate go in PricingOptions (core rule 8)" ($t -match 'PricingOptions')
    }
    Add-Check $c "progress.md has a /plan entry" ($null -ne (Get-LastEntry (Read-WorkFile $Ws "progress.md") "plan"))
    Test-RepoUntouched $Ws $c
    return $c
}

function Test-TasksShape($Ws, [switch]$NoExec) {
    $c = New-Checks
    $t = Read-WorkFile $Ws "tasks.md"
    Add-Check $c "tasks.md exists" ($null -ne $t)
    $tasks = Get-Tasks $t
    Add-Check $c "1 or more tasks" ($tasks.Count -ge 1)
    $guide = [IO.File]::ReadAllText((Join-Path $Ws.Repo "AGENTS.md"))
    $cmds = @([regex]::Matches((Get-MdSection $guide "Commands"), '(?m)^\|[^|]+\|\s*`([^`]+)`') | ForEach-Object { ($_.Groups[1].Value -split ' --filter')[0].Trim() })
    foreach ($k in $tasks) {
        Add-Check $c "task $($k.N): one repo" ($k.Repo -and $k.Repo.Trim('`') -eq "sample-api") "Repo: $($k.Repo)"
        Add-Check $c "task $($k.N): 3 files or fewer" ($k.Files.Count -ge 1 -and $k.Files.Count -le 3) "$($k.Files.Count) files"
        Add-Check $c "task $($k.N): has a Human interface line" ($k.Human -and $k.Human -notmatch '^<')
        $v = if ($k.Verify) { $k.Verify.Trim('`').Trim() } else { "" }
        Add-Check $c "task $($k.N): verify command comes from the repo guide" (@($cmds | Where-Object { $v.StartsWith($_) }).Count -ge 1) "Verify: $v"
        Add-Check $c "task $($k.N): not started" (-not $k.Done)
    }
    $cov = Get-MdSection $t "Coverage check"
    $unc = @("AC-1", "AC-2", "AC-3" | Where-Object { $cov -notmatch [regex]::Escape($_) })
    Add-Check $c "coverage table covers every AC" ($unc.Count -eq 0) "not covered: $($unc -join ', ')"
    $e = Get-LastEntry (Read-WorkFile $Ws "progress.md") "tasks"
    Add-Check $c "/tasks Stats line counts the tasks" ((Get-StatValue $e "tasks") -eq "$($tasks.Count)") "tasks=$(Get-StatValue $e 'tasks'), file has $($tasks.Count)"
    Test-RepoUntouched $Ws $c
    return $c
}

function Test-DoTask($Ws, [switch]$NoExec) {
    $c = New-Checks
    $tasks = Get-Tasks (Read-WorkFile $Ws "tasks.md")
    $t1 = @($tasks | Where-Object { $_.N -eq 1 })[0]
    Add-Check $c "task 1 is checked" ($t1 -and $t1.Done)
    $count = [int](Invoke-EvalGit $Ws.Repo @("rev-list", "--count", "$($Ws.Base)..HEAD"))
    Add-Check $c "exactly one new commit" ($count -eq 1) "$count commits"
    $changed = @((Invoke-EvalGit $Ws.Repo @("diff", "--name-only", $Ws.Base, "HEAD")) -split "\r?\n" | Where-Object { $_ })
    $allowed = @($t1.Files | ForEach-Object { $_ -replace '^sample-api/', '' })
    $extra = @($changed | Where-Object { $allowed -notcontains $_ })
    Add-Check $c "only the task's files changed" ($changed.Count -gt 0 -and $extra.Count -eq 0) "outside the task: $($extra -join ', ')"
    $status = Invoke-EvalGit $Ws.Repo @("status", "--porcelain")
    Add-Check $c "nothing left uncommitted" (-not $status) $status
    $totals = [IO.File]::ReadAllText((Join-Path $Ws.Repo "src/Orders/OrderTotals.cs"))
    $opts = [IO.File]::ReadAllText((Join-Path $Ws.Repo "src/Orders/PricingOptions.cs"))
    Add-Check $c "kept LegacyRound (Do not touch)" ($totals -match 'LegacyRound')
    Add-Check $c "threshold and rate live in PricingOptions" (($opts -match '=\s*10\s*;') -and ($opts -match '0?\.05m') -and ($totals -notmatch '0?\.05m') -and ($totals -notmatch '[<>]=?\s*10\b'))
    $e = Get-LastEntry (Read-WorkFile $Ws "progress.md") "do-task"
    Add-Check $c "progress has a Red run showing a failure" ($e -and $e -match '(?ms)Red run.*?```.*?(Fail|FAIL|Assert)') "no Red run block with a failure"
    Add-Check $c "progress has a Green run" ($e -and $e -match '(?ms)Green run.*?```.*?(Pass|PASS)')
    Add-Check $c "Stats: verify=PASS full=PASS" ((Get-StatValue $e "verify") -eq "PASS" -and (Get-StatValue $e "full") -eq "PASS") "verify=$(Get-StatValue $e 'verify') full=$(Get-StatValue $e 'full')"
    if (-not $NoExec) {
        $proj = Join-Path $Ws.Repo "tests/Orders.Tests"
        Copy-Item -LiteralPath (Join-Path $script:EvalsRoot "fixtures/hidden/BulkDiscountAcceptanceTests.cs") -Destination $proj -Force
        try {
            Push-Location $Ws.Root
            $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
            $out = & dotnet test "sample-api/tests/Orders.Tests/Orders.Tests.csproj" 2>&1 | Out-String
            $ok = ($LASTEXITCODE -eq 0)
            $ErrorActionPreference = $prev
            Pop-Location
            Add-Check $c "all tests pass, including hidden acceptance tests" $ok (($out -split "\r?\n" | Select-Object -Last 15) -join " / ")
        }
        finally { Remove-Item -LiteralPath (Join-Path $proj "BulkDiscountAcceptanceTests.cs") -Force -ErrorAction SilentlyContinue }
    }
    return $c
}

function Get-FindingRows([string]$Review) {
    return @([regex]::Matches($Review, '(?m)^\|\s*\d+\s*\|\s*(Blocker|Should fix|Nit)\s*\|\s*([^|]*)\|([^\r\n]*)') | ForEach-Object {
            [pscustomobject]@{ Severity = $_.Groups[1].Value; Category = $_.Groups[2].Value.Trim().ToLowerInvariant(); Rest = $_.Groups[3].Value }
        })
}

function Test-ReviewPlanted($Ws, [switch]$NoExec) {
    $c = New-Checks
    $t = Read-WorkFile $Ws "review.md"
    Add-Check $c "review.md exists" ($null -ne $t)
    if ($t) {
        Add-Check $c "verdict is CHANGES NEEDED" ($t -match '(?mi)^\s*Verdict:\s*CHANGES NEEDED')
        $p1 = Get-MdSection $t "Pass 1"
        $acRow = [regex]::Match($p1, '(?m)^\|\s*AC-1\s*\|\s*([^|]+)\|')
        $acFlag = $acRow.Success -and $acRow.Groups[1].Value -match '(?i)not met|partly'
        $rows = @(Get-FindingRows $t)
        $hit = @($rows | Where-Object { $_.Severity -eq "Blocker" -and $_.Rest -match '(?i)\b10\b|threshold|>=|at least|AC-1|exactly ten|boundary' })
        Add-Check $c "caught the planted off-by-one (AC-1 not met, or a Blocker on the threshold)" ($acFlag -or $hit.Count -gt 0) "AC-1: $($acRow.Groups[1].Value.Trim()); Blockers: $(@($rows | Where-Object { $_.Severity -eq 'Blocker' }).Count)"
        $badCat = @($rows | Where-Object { $script:AllowedCategories -notcontains $_.Category })
        Add-Check $c "every finding has a known category" ($rows.Count -gt 0 -and $badCat.Count -eq 0) "unknown: $(@($badCat | ForEach-Object { $_.Category }) -join ', ')"
    }
    Add-Check $c "progress has a /review entry with Stats" ($null -ne (Get-StatValue (Get-LastEntry (Read-WorkFile $Ws "progress.md") "review") "verdict"))
    Test-RepoUntouched $Ws $c
    return $c
}

function Test-ReviewClean($Ws, [switch]$NoExec) {
    $c = New-Checks
    $t = Read-WorkFile $Ws "review.md"
    Add-Check $c "review.md exists" ($null -ne $t)
    if ($t) {
        Add-Check $c "verdict is READY" ($t -match '(?mi)^\s*Verdict:\s*READY')
        $rows = @(Get-FindingRows $t)
        $bl = @($rows | Where-Object { $_.Severity -eq "Blocker" })
        Add-Check $c "no false Blockers" ($bl.Count -eq 0) "$($bl.Count) Blockers: $(@($bl | ForEach-Object { $_.Rest }) -join ' | ')"
        $badCat = @($rows | Where-Object { $script:AllowedCategories -notcontains $_.Category })
        Add-Check $c "every finding has a known category" ($badCat.Count -eq 0) "unknown: $(@($badCat | ForEach-Object { $_.Category }) -join ', ')"
    }
    Test-RepoUntouched $Ws $c
    return $c
}

function Test-BugLane($Ws, [switch]$NoExec) {
    $c = New-Checks
    $t = Test-GateFile $Ws $c "bug.md"
    if ($t) {
        Add-Check $c "states a confidence" ($t -match '(?i)\*\*Confidence:\*\*\s*(High|Medium|Low)')
        Add-Check $c "code path reaches OrderTotals.cs" ((Get-MdSection $t "Code path") -match 'OrderTotals\.cs')
    }
    $tasks = Get-Tasks (Read-WorkFile $Ws "tasks.md")
    Add-Check $c "1 to 3 tasks" ($tasks.Count -ge 1 -and $tasks.Count -le 3) "$($tasks.Count) tasks"
    $t1 = @($tasks | Where-Object { $_.N -eq 1 })[0]
    Add-Check $c "task 1 is a test that must fail first" ($t1 -and ($t1.DoneWhen -match '(?i)fail'))
    $e = Get-LastEntry (Read-WorkFile $Ws "progress.md") "bug"
    Add-Check $c "/bug Stats line counts the tasks" ((Get-StatValue $e "tasks") -eq "$($tasks.Count)") "tasks=$(Get-StatValue $e 'tasks')"
    Test-RepoUntouched $Ws $c
    return $c
}

function Test-RetroRepeat($Ws, [switch]$NoExec) {
    $c = New-Checks
    $dir = Join-Path $Ws.Root ".work/_retro"
    $files = @(if (Test-Path -LiteralPath $dir) { Get-ChildItem -LiteralPath $dir -Filter *.md -File })
    Add-Check $c "wrote .work/_retro/<date>.md" ($files.Count -ge 1)
    if ($files.Count -ge 1) {
        $t = [IO.File]::ReadAllText($files[0].FullName)
        Add-Check $c "names the repeating pattern (sample-api, consistency)" ($t -match 'sample-api' -and $t -match '(?i)consistency')
        $rule = $t -match '/memory\s+sample-api\b'
        $broken = (Get-MdSection $t "Rules that exist but were broken") -match 'PricingOptions'
        Add-Check $c "proposes a repo rule, or flags the PricingOptions rule as broken" ($rule -or $broken)
    }
    $status = Invoke-EvalGit $Ws.Repo @("status", "--porcelain")
    Add-Check $c "wrote no memory or repo guide changes" (-not $status) $status
    return $c
}

function Test-QuickLane($Ws, [switch]$NoExec) {
    $c = New-Checks
    $t = Test-GateFile $Ws $c "quick.md"
    if ($t) {
        $acs = @([regex]::Matches($t, '(?m)^\s*-\s*\*\*AC-\d+:\*\*\s*(.+)$') | ForEach-Object { $_.Groups[1].Value })
        $bad = @($acs | Where-Object { $_ -notmatch '(?i)\bgiven\b' -or $_ -notmatch '(?i)\bwhen\b' -or $_ -notmatch '(?i)\bthen\b' })
        Add-Check $c "acceptance criteria are Given / when / then" ($acs.Count -ge 1 -and $bad.Count -eq 0) "found $($acs.Count), not GWT: $($bad.Count)"
        $pm = [regex]::Match($t, '(?mi)^\s*Pattern to follow:\s*`([^`]+)`')
        Add-Check $c "the pattern file exists" ($pm.Success -and (Test-Path -LiteralPath (Join-Path $Ws.Root ($pm.Groups[1].Value -replace ':\d+$', ''))))
        $missing = @(Get-CitedPaths (Get-MdSection $t "Current behavior") | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Ws.Root $_)) })
        Add-Check $c "cited paths exist" ($missing.Count -eq 0) "missing: $($missing -join ', ')"
    }
    $tasks = Get-Tasks (Read-WorkFile $Ws "tasks.md")
    Add-Check $c "1 or 2 tasks" ($tasks.Count -ge 1 -and $tasks.Count -le 2) "$($tasks.Count) tasks"
    $guide = [IO.File]::ReadAllText((Join-Path $Ws.Repo "AGENTS.md"))
    $cmds = @([regex]::Matches((Get-MdSection $guide "Commands"), '(?m)^\|[^|]+\|\s*`([^`]+)`') | ForEach-Object { ($_.Groups[1].Value -split ' --filter')[0].Trim() })
    foreach ($k in $tasks) {
        Add-Check $c "task $($k.N): 3 files or fewer" ($k.Files.Count -ge 1 -and $k.Files.Count -le 3) "$($k.Files.Count) files"
        $v = if ($k.Verify) { $k.Verify.Trim('`').Trim() } else { "" }
        Add-Check $c "task $($k.N): verify command comes from the repo guide" (@($cmds | Where-Object { $v.StartsWith($_) }).Count -ge 1) "Verify: $v"
    }
    $repos = Read-WorkFile $Ws "repos.md"
    Add-Check $c "stays in the quick lane" ($repos -match '(?mi)^\s*Lane:\s*quick\s*$')
    $e = Get-LastEntry (Read-WorkFile $Ws "progress.md") "quick"
    Add-Check $c "/quick Stats line counts the tasks" ((Get-StatValue $e "tasks") -eq "$($tasks.Count)") "tasks=$(Get-StatValue $e 'tasks')"
    Test-RepoUntouched $Ws $c
    return $c
}

function Test-QuickEscalate($Ws, [switch]$NoExec) {
    $c = New-Checks
    $repos = Read-WorkFile $Ws "repos.md"
    Add-Check $c "switched repos.md to the feature lane" ($repos -match '(?mi)^\s*Lane:\s*feature\s*$')
    Add-Check $c "kept the branch" ($repos -match 'dev/feature/L4-save-orders-http')
    Add-Check $c "wrote no quick.md" ($null -eq (Read-WorkFile $Ws "quick.md"))
    Add-Check $c "wrote no tasks.md" ($null -eq (Read-WorkFile $Ws "tasks.md"))
    $e = Get-LastEntry (Read-WorkFile $Ws "progress.md") "quick"
    Add-Check $c "logged escalated=1" ((Get-StatValue $e "escalated") -eq "1")
    Test-RepoUntouched $Ws $c
    return $c
}

# Every file the run changed in sample-api since the start: committed, staged, unstaged and untracked.
function Get-ChangedFiles($Ws) {
    $set = New-Object System.Collections.Generic.HashSet[string]
    foreach ($f in ((Invoke-EvalGit $Ws.Repo @("diff", "--name-only", $Ws.Base, "HEAD")) -split "\r?\n")) { if ($f) { [void]$set.Add($f.Trim()) } }
    foreach ($line in ((Invoke-EvalGit $Ws.Repo @("status", "--porcelain", "-uall")) -split "\r?\n")) {
        if (-not $line.Trim()) { continue }
        # "XY path" (Invoke-EvalGit trims the output, so the first line may have lost its leading space)
        $path = ($line -replace '^\s*[A-Z?!]{1,2}\s+', '').Trim().Trim('"')
        if ($path -match ' -> ') { $path = ($path -split ' -> ')[-1] }
        [void]$set.Add($path)
    }
    return @($set | Sort-Object)
}

# Outcome only, for Tandem and a plain prompt alike (feature-outcome): does the feature work, and did the run stay in
# bounds? Nothing about .work files, commits or how the agent got there.
function Test-FeatureOutcome($Ws, [switch]$NoExec) {
    $c = New-Checks
    $changed = @(Get-ChangedFiles $Ws)
    Add-Check $c "changed the code" ($changed.Count -gt 0) "no changes in sample-api"
    $outside = @($changed | Where-Object { $_ -notmatch '^(src|tests)/' })
    Add-Check $c "changes only in src/ and tests/" ($outside.Count -eq 0) "outside: $($outside -join ', ')"
    $totals = [IO.File]::ReadAllText((Join-Path $Ws.Repo "src/Orders/OrderTotals.cs"))
    $opts = [IO.File]::ReadAllText((Join-Path $Ws.Repo "src/Orders/PricingOptions.cs"))
    Add-Check $c "kept LegacyRound (Do not touch)" ($totals -match 'LegacyRound')
    Add-Check $c "threshold and rate live in PricingOptions" (($opts -match '=\s*10\s*;') -and ($opts -match '0?\.05m') -and ($totals -notmatch '0?\.05m') -and ($totals -notmatch '[<>]=?\s*10\b'))
    if (-not $NoExec) {
        $proj = Join-Path $Ws.Repo "tests/Orders.Tests"
        $hiddenName = "BulkDiscountOutcomeTests.cs"
        Copy-Item -LiteralPath (Join-Path $script:EvalsRoot "fixtures/hidden-outcome/$hiddenName") -Destination $proj -Force
        try {
            Push-Location $Ws.Root
            $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
            $out = & dotnet test "sample-api/tests/Orders.Tests/Orders.Tests.csproj" 2>&1 | Out-String
            $ok = ($LASTEXITCODE -eq 0)
            $ErrorActionPreference = $prev
            Pop-Location
            Add-Check $c "all tests pass, including hidden outcome tests" $ok (($out -split "\r?\n" | Select-Object -Last 15) -join " / ")
        }
        finally { Remove-Item -LiteralPath (Join-Path $proj $hiddenName) -Force -ErrorAction SilentlyContinue }
    }
    return $c
}

