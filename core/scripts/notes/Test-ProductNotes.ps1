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
$know = Join-Path $PSScriptRoot "Get-Knowledge.ps1"
function Run([string]$Script, [string[]]$Arguments) {
    $ErrorActionPreference = "Continue"   # Windows PowerShell 5.1 turns a child's stderr into errors
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
    $file = Join-Path $data "folio/products/wiki-edge.md"
    $text = if (Test-Path $file) { [IO.File]::ReadAllText($file) } else { "" }
    Check "create from the built-in template" ($r.Code -eq 0 -and $text -match "(?m)^title: Wiki Edge$" -and $text -match "product/wiki-edge" -and $text -match "(?m)^repos: \[wiki-edge-api, wiki-edge-web\]$" -and $text -match "(?m)^tandem-changed: \d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$") "$($r.Out) $text"

    $r = Run $set @("-Product", "wiki-edge", "-Line", "Exports are capped at 5k rows.", "-Source", "PR 4812")
    $text = [IO.File]::ReadAllText($file)
    Check "add a line to Remembered" ($r.Code -eq 0 -and $text -match "## Remembered\r?\n\r?\n- Exports are capped at 5k rows\. \(\d{4}-\d\d-\d\d, PR 4812\)") "$($r.Out) $text"
    $hist = Join-Path $data "folio/history/products-wiki-edge-11izt4n"
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
    Check "older versions in the trash" (Test-Path (Join-Path $data ".trash/folio/history/products-wiki-edge-11izt4n"))
    Check "no temp files left" (@(Get-ChildItem (Join-Path $data "folio/products") -Force -File | Where-Object { $_.Name -like ".tandem-*" }).Count -eq 0)

    # A template in Notes wins over the built-in one.
    New-Item -ItemType Directory -Path (Join-Path $data "folio/templates") -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $data "folio/templates/product.md"), "---`ntitle: {{title}}`ntags: [product, product/{{slug}}]`n---`n# {{title}}`n`n## Mine`n")
    $r = Run $set @("-Product", "Stencil", "-Create")
    $text = [IO.File]::ReadAllText((Join-Path $data "folio/products/stencil.md"))
    Check "create from templates/product.md" ($text -match "## Mine" -and $text -match "product/stencil") $text

    $r = Run $get @("-List")
    Check "list" ($r.Out -match "products/stencil\.md\s+Stencil" -and $r.Out -match "products/wiki-edge\.md\s+Wiki Edge\s+\(changed by Tandem") $r.Out
    $r = Run $get @("-Product", "Wiki Edge")
    Check "read one" ($r.Out -match "Product note: products/wiki-edge\.md" -and $r.Out -match "10k rows") $r.Out
    $r = Run $get @("-Product", "Nope")
    Check "read a missing one" ($r.Code -eq 0 -and $r.Out -match "does not exist yet") $r.Out

    # Flags: a line the code contradicts gets "(check: ...)" and the note needs review again.
    $r = Run $set @("-Product", "wiki-edge", "-Flag", "capped at 10k", "-Reason", "ExportService (now) uses 20000", "-Source", "src/Export.cs")
    $text = [IO.File]::ReadAllText($file)
    Check "flag a contradicted line" ($r.Code -eq 0 -and $text -match "10k rows\. \(\d{4}-\d\d-\d\d, PR 5000\) \(check: ExportService now uses 20000, \d{4}-\d\d-\d\d, src/Export\.cs\)") "$($r.Out) $text"
    $r = Run $set @("-Product", "wiki-edge", "-Flag", "capped at 10k", "-Reason", "again", "-Source", "x")
    Check "a flagged line is flagged once" ($r.Code -eq 0 -and $r.Out -match "Already flagged") $r.Out
    $r = Run $set @("-Product", "wiki-edge", "-Flag", "capped at 10k", "-Source", "x")
    Check "a flag needs a reason" ($r.Code -eq 1) $r.Out

    # The team handbook and the change log: made from the built-in templates on the first line.
    $r = Run $set @("-Note", "team/handbook.md", "-Section", "Pull requests", "-Line", "Two approvals before merge.", "-Source", "the engineer")
    $hb = Join-Path $data "folio/team/handbook.md"
    $text = if (Test-Path $hb) { [IO.File]::ReadAllText($hb) } else { "" }
    Check "handbook made and written" ($r.Code -eq 0 -and $text -match "(?m)^title: Team handbook$" -and $text -match "## Pull requests\r?\n\r?\n- Two approvals before merge\." -and $text -match "(?m)^tandem-changed: ") "$($r.Out) $text"
    $r = Run $set @("-Note", "../secrets.md", "-Line", "x", "-Source", "y")
    Check "only the allowed notes" ($r.Code -eq 1 -and $r.Out -match "must be") $r.Out
    $r = Run $set @("-Note", "team/handbook.md", "-Create")
    Check "-Create is for product notes" ($r.Code -eq 1) $r.Out
    for ($i = 0; $i -lt 103; $i++) { Run $set @("-Note", "changes", "-Line", "api repo guide, Remembered: rule $i.", "-Source", "/memory") | Out-Null }
    $log = [IO.File]::ReadAllText((Join-Path $data "folio/tandem/changes.md"))
    $bul = @($log -split "\r?\n" | Where-Object { $_ -match '^- ' })
    Check "the change log keeps the newest 100" ($bul.Count -eq 100 -and $bul[0] -match "rule 3\." -and $bul[-1] -match "rule 102\." -and $log -match "## Changes") "$($bul.Count) $($bul[0])"

    # Get-Knowledge: one block from Settings, People, the note and the handbook.
    $settings = Join-Path $data "settings"
    New-Item -ItemType Directory -Path $settings -Force | Out-Null
    $env1 = { param($name, $ver, $items) (@{ schema = "settings.$name"; version = $ver; rev = 1; items = $items; deleted = @{} } | ConvertTo-Json -Depth 6) }
    [IO.File]::WriteAllText((Join-Path $settings "products.json"), (& $env1 "products" 1 @(
        @{ id = "p_wiki-edge"; updatedAt = 1; name = "Wiki Edge"; slug = "wiki-edge"; alsoCalled = @("wiki"); repos = @("Platform/wiki-edge-api"); areas = @("Project\Wiki"); changeOrder = @("shared-lib", "Platform/wiki-edge-api"); processes = @("Publish a page") },
        @{ id = "p_old"; updatedAt = 1; name = "Old"; slug = "old"; archived = $true })))
    [IO.File]::WriteAllText((Join-Path $settings "people.json"), (& $env1 "people" 2 @(
        @{ id = "p_a"; kind = "person"; updatedAt = 1; name = "Person One"; handle = "person"; relation = "report"; role = "Senior Engineer"; owns = @("wiki-edge-api") },
        @{ id = "p_b"; kind = "person"; updatedAt = 1; name = "Gone Person"; handle = "gone"; relation = "peer"; archived = $true; owns = @("wiki") })))
    [IO.File]::WriteAllText((Join-Path $settings "glossary.json"), (& $env1 "glossary" 1 @(
        @{ id = "g_page"; updatedAt = 1; term = "Page"; code = "Article"; productId = "p_wiki-edge"; where = "src/Article.cs" },
        @{ id = "g_any"; updatedAt = 1; term = "Plan year"; code = "CoverageYear" },
        @{ id = "g_other"; updatedAt = 1; term = "Route"; code = "GatewayRoute"; productId = "p_other" })))
    $r = Run $know @("-Product", "WIKI")
    $o = $r.Out
    Check "knowledge: found by another name, Settings fields" ($r.Code -eq 0 -and $o -match "# Knowledge: Wiki Edge" -and $o -match "- Change order: shared-lib, then Platform/wiki-edge-api" -and $o -match "- Business processes: Publish a page") $o
    Check "knowledge: owners from People, archived left out" ($o -match "- Person One, Senior Engineer \(owns wiki-edge-api\)" -and $o -notmatch "Gone Person") $o
    Check "knowledge: the product's words, then any product's (a word whose product is gone counts as any)" ($o -match "- Page = ``Article`` \(src/Article\.cs\)" -and $o -match "- Plan year = ``CoverageYear``" -and $o -match "- Route = ``GatewayRoute``") $o
    Check "knowledge: the note without its frontmatter, and the handbook" ($o -match "10k rows" -and $o -notmatch "(?m)^tandem-changed:" -and $o -match "Two approvals before merge") $o
    Check "knowledge: ends with its sources" ($o -match "Sources: settings/products\.json, settings/people\.json, settings/glossary\.json, folio/products/wiki-edge\.md, folio/team/handbook\.md") $o
    $r = Run $know @("-Product", "Old")
    Check "knowledge: an archived product is not found, the note is still read" ($r.Code -eq 0 -and $r.Out -match "Not a product in Workshop Settings") $r.Out
    $r = Run $know @("-Product", "Wiki Edge", "-MaxLines", "40")
    Check "knowledge: the handbook is cut first when it is long" ($r.Out -match "Handbook cut here") $r.Out
    $r = Run $know @("-Handbook")
    Check "knowledge: the handbook alone" ($r.Code -eq 0 -and $r.Out -match "Team handbook: folio/team/handbook\.md" -and $r.Out -match "Two approvals") $r.Out
    [IO.File]::WriteAllText((Join-Path $settings "products.json"), (& $env1 "products" 2 @()))
    $r = Run $know @("-Product", "Wiki Edge")
    Check "knowledge: products from a newer Workshop are skipped, not an error" ($r.Code -eq 0 -and $r.Out -match "Not a product" -and $r.Out -match "10k rows") $r.Out

    # A Workshop that has not renamed notes/ to folio/ yet: the old folder is used while it is the only one.
    $old = Join-Path $root "old"
    New-Item -ItemType Directory -Path (Join-Path $old "notes/products") -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $wsHome "config.json"), (@{ dataDir = $old } | ConvertTo-Json))
    $r = Run $set @("-Product", "Lighthouse", "-Create")
    Check "an old notes/ folder is used while there is no folio/" ($r.Code -eq 0 -and (Test-Path (Join-Path $old "notes/products/lighthouse.md")) -and -not (Test-Path (Join-Path $old "folio"))) $r.Out
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:WORKSHOP_HOME -ErrorAction SilentlyContinue
}

if ($failed) { Write-Output "$failed failed"; exit 1 }
Write-Output "all passed"
