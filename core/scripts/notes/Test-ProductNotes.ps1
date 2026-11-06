<#
.SYNOPSIS
  Self-test for the product note scripts. Uses a temp Workshop home and data folder; touches nothing else.
  Run: pwsh -NoProfile -File core/scripts/notes/Test-ProductNotes.ps1   (also works in Windows PowerShell 5.1)
#>
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "ProductNotes.ps1")

$failed = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = "") {
    if ($Ok) { Write-Output "ok   $Name" } else { Write-Output "FAIL $Name $Detail"; $script:failed++ }
}

$ps = (Get-Process -Id $PID).Path
$get = Join-Path $PSScriptRoot "Get-ProductNote.ps1"
$set = Join-Path $PSScriptRoot "Set-ProductNote.ps1"
function Run([string]$Script, [string[]]$Arguments) {
    $out = & $ps -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments 2>&1 | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}

# Same key and stamp as Notes' js/history.js (checked against Notes 2.1.0).
Check "history key" ((Get-NotesHistoryKey "products/wiki-edge.md") -eq "products-wiki-edge-11izt4n") (Get-NotesHistoryKey "products/wiki-edge.md")
Check "stamp" ((Get-NotesStamp ([datetime]::new(2026, 11, 5, 17, 12, 30, 123, [DateTimeKind]::Utc))) -eq "20261105t171230123z.md")
Check "slug" ((ConvertTo-NoteSlug "Wiki Edge (v2)") -eq "wiki-edge-v2")

$root = Join-Path ([IO.Path]::GetTempPath()) ("pn-" + [guid]::NewGuid().ToString("N"))
$wsHome = Join-Path $root "home"
$data = Join-Path $root "data"
New-Item -ItemType Directory -Path $wsHome, $data -Force | Out-Null
$env:WORKSHOP_HOME = $wsHome
try {
    $r = Run $get @("-List")
    Check "no Workshop: not available, exit 0" ($r.Code -eq 0 -and $r.Out -match "not available") $r.Out

    [IO.File]::WriteAllText((Join-Path $wsHome "config.json"), (@{ dataDir = $data } | ConvertTo-Json))
    [IO.File]::WriteAllText((Join-Path $wsHome "apps.json"), '{"off": ["notes"]}')
    $r = Run $set @("-Product", "Wiki Edge", "-Create")
    Check "Notes off: refused" ($r.Code -eq 1 -and $r.Out -match "switched off") $r.Out
    Remove-Item (Join-Path $wsHome "apps.json")

    $r = Run $set @("-Product", "Wiki Edge", "-Line", "x", "-Source", "PR 1")
    Check "missing note: refused" ($r.Code -eq 1 -and $r.Out -match "-Create") $r.Out

    $r = Run $set @("-Product", "Wiki Edge", "-Create", "-Repos", "wiki-edge-api,wiki-edge-web", "-AlsoCalled", "wiki")
    $file = Join-Path $data "notes/products/wiki-edge.md"
    $text = if (Test-Path $file) { [IO.File]::ReadAllText($file) } else { "" }
    Check "create from the built-in template" ($r.Code -eq 0 -and $text -match "(?m)^title: Wiki Edge$" -and $text -match "product/wiki-edge" -and $text -match "(?m)^repos: \[wiki-edge-api, wiki-edge-web\]$" -and $text -match "(?m)^tandem-changed: \d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$") "$($r.Out) $text"

    $r = Run $set @("-Product", "wiki-edge", "-Line", "Exports are capped at 5k rows.", "-Source", "PR 4812")
    $text = [IO.File]::ReadAllText($file)
    Check "add a line to Remembered" ($r.Code -eq 0 -and $text -match "## Remembered\r?\n\r?\n- Exports are capped at 5k rows\. \(\d{4}-\d\d-\d\d, PR 4812\)") "$($r.Out) $text"
    $hist = Join-Path $data "notes/history/products-wiki-edge-11izt4n"
    Check "snapshot in Notes' history format" ((Test-Path $hist) -and @(Get-ChildItem $hist -File | Where-Object { $_.Name -match '^\d{8}t\d{9}z\.md$' }).Count -eq 1)

    $r = Run $set @("-Product", "wiki-edge", "-Line", "- exports are capped at 5k rows.", "-Source", "PR 9")
    Check "same fact twice: left alone" ($r.Code -eq 0 -and $r.Out -match "Already there") $r.Out

    $r = Run $set @("-Product", "wiki-edge", "-Replace", "capped at 5k", "-Line", "Exports are capped at 10k rows.", "-Source", "PR 5000")
    $text = [IO.File]::ReadAllText($file)
    Check "replace a wrong line" ($r.Code -eq 0 -and $text -notmatch "5k rows" -and $text -match "10k rows\. \(\d{4}-\d\d-\d\d, PR 5000\)" -and $r.Out -match "Before:") "$($r.Out) $text"

    $r = Run $set @("-Product", "wiki-edge", "-Section", "Gotchas", "-Line", "Search reindex runs nightly.", "-Source", "work item 123")
    $text = [IO.File]::ReadAllText($file)
    Check "add to another section" ($r.Code -eq 0 -and $text -match "## Gotchas\r?\n\r?\n- Search reindex runs nightly\.") $text

    $r = Run $set @("-Product", "wiki-edge", "-Section", "Customers", "-Line", "Used by support.", "-Source", "work item 9")
    $text = [IO.File]::ReadAllText($file)
    Check "missing section is added at the end" ($r.Code -eq 0 -and $text -match "## Customers\r?\n\r?\n- Used by support\.") $text

    $r = Run $set @("-Product", "wiki-edge", "-Line", "- [ ] do a thing", "-Source", "x")
    Check "checklist lines refused" ($r.Code -eq 1) $r.Out
    $r = Run $set @("-Product", "wiki-edge", "-Line", "No source")
    Check "source required" ($r.Code -eq 1) $r.Out

    # reviewed is never touched, and the note keeps its own frontmatter lines.
    $t = [IO.File]::ReadAllText($file) -replace "(?m)^tandem-changed:", "reviewed: 2026-01-01T00:00:00Z`ntandem-changed:"
    [IO.File]::WriteAllText($file, $t)
    $r = Run $set @("-Product", "wiki-edge", "-Line", "Another fact.", "-Source", "PR 2")
    $text = [IO.File]::ReadAllText($file)
    Check "reviewed kept as is" ($text -match "(?m)^reviewed: 2026-01-01T00:00:00Z$" -and $text -match "(?m)^also-called: \[wiki\]$") $text

    # Snapshots are trimmed to the newest 20 (older ones go to the trash).
    for ($i = 0; $i -lt 22; $i++) { Run $set @("-Product", "wiki-edge", "-Line", "Fact $i.", "-Source", "PR $i") | Out-Null; Start-Sleep -Milliseconds 5 }
    Check "history trimmed to 20" (@(Get-ChildItem $hist -File).Count -eq 20) "$(@(Get-ChildItem $hist -File).Count)"
    Check "older versions in the trash" (Test-Path (Join-Path $data ".trash/notes/history/products-wiki-edge-11izt4n"))
    Check "no temp files left" (@(Get-ChildItem (Join-Path $data "notes/products") -Force -File | Where-Object { $_.Name -like ".tandem-*" }).Count -eq 0)

    # A template in Notes wins over the built-in one.
    New-Item -ItemType Directory -Path (Join-Path $data "notes/templates") -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $data "notes/templates/product.md"), "---`ntitle: {{title}}`ntags: [product, product/{{slug}}]`n---`n# {{title}}`n`n## Mine`n")
    $r = Run $set @("-Product", "Stencil", "-Create")
    $text = [IO.File]::ReadAllText((Join-Path $data "notes/products/stencil.md"))
    Check "create from templates/product.md" ($text -match "## Mine" -and $text -match "product/stencil") $text

    $r = Run $get @("-List")
    Check "list" ($r.Out -match "products/stencil\.md\s+Stencil" -and $r.Out -match "products/wiki-edge\.md\s+Wiki Edge\s+\(changed by Tandem") $r.Out
    $r = Run $get @("-Product", "Wiki Edge")
    Check "read one" ($r.Out -match "Product note: products/wiki-edge\.md" -and $r.Out -match "10k rows") $r.Out
    $r = Run $get @("-Product", "Nope")
    Check "read a missing one" ($r.Code -eq 0 -and $r.Out -match "does not exist yet") $r.Out
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:WORKSHOP_HOME -ErrorAction SilentlyContinue
}

if ($failed) { Write-Output "$failed failed"; exit 1 }
Write-Output "all passed"
