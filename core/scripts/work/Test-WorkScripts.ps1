<#
.SYNOPSIS
  Self-test for Add-Observation.ps1, Add-Gap.ps1, Close-Gap.ps1, Find-Repeats.ps1 and New-Worktree.ps1. Writes only to a temp folder. Needs git.
  Run: pwsh -NoProfile -File core/scripts/work/Test-WorkScripts.ps1   (also works in Windows PowerShell 5.1)
#>
$ErrorActionPreference = "Stop"

$failed = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = "") {
    if ($Ok) { Write-Output "ok   $Name" } else { Write-Output "FAIL $Name $Detail"; $script:failed++ }
}

$ps = (Get-Process -Id $PID).Path
function Run([string]$Script, [string[]]$Arguments) {
    $ErrorActionPreference = "Continue"
    $out = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $Script) @Arguments 2>&1 | Out-String
    return @{ Out = $out.Trim(); Code = $LASTEXITCODE; Last = (($out.Trim() -split "\r?\n") | Select-Object -Last 1) }
}
function G([string[]]$Arguments) {
    $ErrorActionPreference = "Continue"
    $out = & git @Arguments 2>&1 | Out-String
    return $out.Trim()
}

$root = Join-Path ([IO.Path]::GetTempPath()) ("work-" + [guid]::NewGuid().ToString("N"))
$wr = Join-Path $root ".work"
New-Item -ItemType Directory -Path $root -Force | Out-Null

try {
    # ---------------------------------------------------------------- observations
    $r = Run "Add-Observation.ps1" @("-WorkRoot", $wr, "-Kind", "bug", "-Repo", "api", "-Source", "12345", "-Text", "ExportJob swallows the timeout")
    Check "observation: first gets O1" ($r.Last -eq "O1") $r.Out
    $text = [IO.File]::ReadAllText((Join-Path $wr "observations.md"))
    Check "observation: header written" ($text -match '^# Observations')
    Check "observation: line format" ($text -match "(?m)^- O1 \| \d{4}-\d{2}-\d{2} \| bug \| api \| 12345 \| ExportJob swallows the timeout$") $text

    $r = Run "Add-Observation.ps1" @("-WorkRoot", $wr, "-Kind", "debt", "-Repo", "API", "-Text", "  exportjob   swallows the TIMEOUT ")
    Check "observation: same repo and text is a duplicate" ($r.Last -eq "DUPLICATE: O1") $r.Out

    $r = Run "Add-Observation.ps1" @("-WorkRoot", $wr, "-Kind", "docs", "-Text", "README has | a pipe`nand a newline")
    Check "observation: second gets O2" ($r.Last -eq "O2") $r.Out
    $text = [IO.File]::ReadAllText((Join-Path $wr "observations.md"))
    Check "observation: pipes and newlines cleaned, repo defaults to -" ($text -match "(?m)^- O2 \| [^|]+ \| docs \| - \| - \| README has / a pipe and a newline$") $text

    $long = "x" * 300
    $r = Run "Add-Observation.ps1" @("-WorkRoot", $wr, "-Kind", "idea", "-Text", $long)
    $line = ([IO.File]::ReadAllText((Join-Path $wr "observations.md")) -split "\r?\n") | Where-Object { $_ -match '^- O3 ' }
    Check "observation: long text cut to 200" (($line -split '\| ')[-1].Length -eq 200) "$line"

    # Ids are never reused, even when the file loses lines.
    [IO.File]::WriteAllText((Join-Path $wr "observations.md"), "# Observations`n`n")
    $r = Run "Add-Observation.ps1" @("-WorkRoot", $wr, "-Kind", "tests", "-Text", "No test for retry")
    Check "observation: ids never reused" ($r.Last -eq "O4") $r.Out

    $r = Run "Add-Observation.ps1" @("-WorkRoot", $wr, "-Kind", "nope", "-Text", "x")
    Check "observation: bad kind refused" ($r.Code -ne 0)

    # ---------------------------------------------------------------- gaps
    $r = Run "Add-Gap.ps1" @("-WorkRoot", $wr, "-Kind", "fact", "-Product", "Sample Portal", "-Source", "L12", "-Question", "May a refund exceed the order total?", "-Assumed", "No, capped at the total")
    Check "gap: first gets G1" ($r.Last -eq "G1") $r.Out
    $text = [IO.File]::ReadAllText((Join-Path $wr "gaps.md"))
    Check "gap: header written" ($text -match '^# Knowledge gaps')
    Check "gap: line format" ($text -match "(?m)^- G1 \| \d{4}-\d{2}-\d{2} \| fact \| Sample Portal \| L12 \| May a refund exceed the order total\? \| No, capped at the total \| open$") $text
    $r = Run "Add-Gap.ps1" @("-WorkRoot", $wr, "-Kind", "term", "-Product", "sample portal", "-Question", "  may a refund EXCEED the order total? ")
    Check "gap: same product and question is a duplicate" ($r.Last -eq "DUPLICATE: G1") $r.Out
    $r = Run "Add-Gap.ps1" @("-WorkRoot", $wr, "-Kind", "repo", "-Question", "Which repo | owns`nexports?")
    Check "gap: second gets G2, defaults to -" ($r.Last -eq "G2") $r.Out
    $text = [IO.File]::ReadAllText((Join-Path $wr "gaps.md"))
    Check "gap: pipes and newlines cleaned, no assumption is -" ($text -match "(?m)^- G2 \| [^|]+ \| repo \| - \| - \| Which repo / owns exports\? \| - \| open$") $text
    $r = Run "Add-Gap.ps1" @("-WorkRoot", $wr, "-Kind", "nope", "-Question", "x")
    Check "gap: bad kind refused" ($r.Code -ne 0)
    $r = Run "Close-Gap.ps1" @("-WorkRoot", $wr, "-Id", "G1", "-Where", "products/sample-portal.md, Rules")
    Check "gap: close" ($r.Last -eq "CLOSED: G1") $r.Out
    $text = [IO.File]::ReadAllText((Join-Path $wr "gaps.md"))
    Check "gap: closed line says where" ($text -match "(?m)^- G1 \|.*\| No, capped at the total \| answered \d{4}-\d{2}-\d{2}: products/sample-portal.md, Rules$") $text
    Check "gap: other lines unchanged" ($text -match "(?m)^- G2 .*\| open$") $text
    $r = Run "Close-Gap.ps1" @("-WorkRoot", $wr, "-Id", "G1", "-Where", "again")
    Check "gap: closing twice says already" ($r.Last -eq "ALREADY: G1") $r.Out
    $r = Run "Close-Gap.ps1" @("-WorkRoot", $wr, "-Id", "G9", "-Where", "x")
    Check "gap: unknown id not found" ($r.Last -eq "NOT FOUND: G9" -and $r.Code -ne 0) $r.Out
    [IO.File]::WriteAllText((Join-Path $wr "gaps.md"), "# Knowledge gaps`n`n")
    $r = Run "Add-Gap.ps1" @("-WorkRoot", $wr, "-Kind", "process", "-Question", "Who approves releases?")
    Check "gap: ids never reused" ($r.Last -eq "G3") $r.Out

    # ---------------------------------------------------------------- repeats (the run retro)
    $rw = Join-Path $root "rep\.work"
    foreach ($i in 1..3) {
        $f = Join-Path $rw "L$i-item-$i"
        New-Item -ItemType Directory -Path $f -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $f "review.md"), "# Review: L$i x`n`nVerdict: READY`n`n## Pass 2: Code quality`n`n| # | Severity | Category | Location | Problem | Suggested fix |`n|---|---|---|---|---|---|`n| 1 | Should fix | leftovers | ``api/src/A$i.cs:3`` | debug log | remove |`n")
    }
    $r = Run "Find-Repeats.ps1" @("-WorkRoot", $rw)
    Check "repeats: a finding in 3 items is suggested" ($r.Out -match "reviews keep finding leftovers problems in api \(3 items" -and $r.Last -eq "REPEATS: 1 new") $r.Out
    foreach ($q in "Is A allowed?", "Is B allowed?", "Is C allowed?") { $null = Run "Add-Gap.ps1" @("-WorkRoot", $rw, "-Kind", "fact", "-Product", "Portal", "-Question", $q) }
    $r = Run "Find-Repeats.ps1" @("-WorkRoot", $rw)
    Check "repeats: 3 gaps of one kind and product are suggested" ($r.Out -match "asked 3 fact questions about Portal" -and $r.Last -eq "REPEATS: 2 new") $r.Out
    Add-Content -LiteralPath (Join-Path $rw ".repeats") -Value "finding|api|leftovers"
    $r = Run "Find-Repeats.ps1" @("-WorkRoot", $rw)
    Check "repeats: a key already suggested is not suggested again" ($r.Out -notmatch "leftovers" -and $r.Last -eq "REPEATS: 1 new") $r.Out
    $r = Run "Find-Repeats.ps1" @("-WorkRoot", (Join-Path $root "none"))
    Check "repeats: no .work is 0" ($r.Last -eq "REPEATS: 0 new") $r.Out

    # ---------------------------------------------------------------- worktrees
    $repo = Join-Path $root "api"
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    G @("-C", $repo, "init", "-q", "-b", "main") | Out-Null
    G @("-C", $repo, "config", "user.email", "t@example.com") | Out-Null
    G @("-C", $repo, "config", "user.name", "Test") | Out-Null
    [IO.File]::WriteAllText((Join-Path $repo "a.txt"), "a")
    G @("-C", $repo, "add", "a.txt") | Out-Null
    G @("-C", $repo, "commit", "-q", "-m", "first") | Out-Null
    G @("-C", $repo, "checkout", "-q", "-b", "dev/feature/1-other") | Out-Null

    $r = Run "New-Worktree.ps1" @("-Workspace", $root, "-Repo", "api", "-Folder", "2-thing", "-Branch", "dev/feature/2-thing", "-Base", "main")
    Check "worktree: prints the relative path" ($r.Last -eq ".worktrees/2-thing/api") $r.Out
    $wt = Join-Path $root ".worktrees/2-thing/api"
    Check "worktree: on the new branch" ((G @("-C", $wt, "branch", "--show-current")) -eq "dev/feature/2-thing")
    Check "worktree: repo folder stays on its branch" ((G @("-C", $repo, "branch", "--show-current")) -eq "dev/feature/1-other")
    Check "worktree: branch visible from the repo folder" ((G @("-C", $repo, "branch", "--list", "dev/feature/2-thing")) -match "2-thing")

    $r = Run "New-Worktree.ps1" @("-Workspace", $root, "-Repo", "api", "-Folder", "2-thing", "-Branch", "dev/feature/2-again", "-Base", "main")
    Check "worktree: existing folder refused" ($r.Code -ne 0 -and $r.Out -match "EXISTS:") $r.Out

    $r = Run "New-Worktree.ps1" @("-Workspace", $root, "-Repo", "nope", "-Folder", "3-x", "-Branch", "dev/feature/3-x", "-Base", "main")
    Check "worktree: unknown repo refused" ($r.Code -ne 0 -and $r.Out -match "NOREPO:") $r.Out

    $r = Run "New-Worktree.ps1" @("-Workspace", $root, "-Repo", "../api", "-Folder", "3-x", "-Branch", "dev/feature/3-x", "-Base", "main")
    Check "worktree: path outside the workspace refused" ($r.Code -ne 0 -and $r.Out -match "NOREPO:") $r.Out

    G @("-C", $repo, "branch", "dev/feature/5-old", "main") | Out-Null
    $r = Run "New-Worktree.ps1" @("-Workspace", $root, "-Repo", "api", "-Folder", "5-old", "-Branch", "dev/feature/5-old", "-Existing")
    Check "worktree: -Existing checks out a made branch" ($r.Code -eq 0 -and (G @("-C", (Join-Path $root ".worktrees/5-old/api"), "branch", "--show-current")) -eq "dev/feature/5-old") $r.Out

    $r = Run "New-Worktree.ps1" @("-Workspace", $root, "-Repo", "api", "-Folder", "6-x", "-Branch", "dev/feature/6-x")
    Check "worktree: no base and no -Existing refused" ($r.Code -ne 0) $r.Out

    $r = Run "New-Worktree.ps1" @("-Workspace", $root, "-Repo", "api", "-Folder", "4-x", "-Branch", "dev/feature/2-thing", "-Base", "main")
    Check "worktree: git refusal reported" ($r.Code -ne 0 -and $r.Out -match "GIT:") $r.Out
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failed) { Write-Output "$failed failed"; exit 1 }
Write-Output "All work script checks passed."
exit 0
