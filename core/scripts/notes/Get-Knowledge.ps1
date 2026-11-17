<#
.SYNOPSIS
  Prints what Tandem needs to know about one product, in one block: its Settings fields, glossary words, owners from
  People, its product note and the team handbook. Or the handbook alone.

.DESCRIPTION
  Workshop keeps each fact in one place (Workshop docs/knowledge.md): products, the glossary and people in Settings'
  folder (<Workshop data folder>/settings/*.json), product notes and the team handbook in Folio's folder. This reads
  them all, read-only, so an agent makes one call instead of reading the repo map block, then the note, then People.

  A product is found by name, another name or slug, case ignored. Missing parts are skipped with one line saying so;
  nothing here is an error (exit 0), so callers go on without it. Over about 400 lines, the handbook is cut first.

.EXAMPLE
  Get-Knowledge.ps1 -Product "Wiki Edge"
  Get-Knowledge.ps1 -Handbook
#>
[CmdletBinding(DefaultParameterSetName = "One")]
param(
    [Parameter(ParameterSetName = "One", Mandatory = $true, Position = 0)] [string]$Product,
    [Parameter(ParameterSetName = "Handbook", Mandatory = $true)] [switch]$Handbook,
    [int]$MaxLines = 400
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "ProductNotes.ps1")

$where = Get-ProductNotesHome
if (-not $where.Ok) {
    Write-Output "Knowledge: not available. $($where.Reason)"
    exit 0
}

# A note's text without its frontmatter.
function Get-NoteBody([string]$File) {
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { return $null }
    $n = Split-Note (Read-NoteText $File)
    return (($n.Lines | Select-Object -Skip $n.Front) -join "`n").Trim()
}
$prop = { param($o, $name) if ($o -and $o.PSObject.Properties.Name -contains $name) { $o.$name } else { $null } }
$names = { param($v) @($v | Where-Object { $_ }) -join ", " }

$handbookFile = Join-Path $where.NotesDir ($script:HandbookPath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
$handbookText = Get-NoteBody $handbookFile

if ($Handbook) {
    if ($null -eq $handbookText) { Write-Output "Team handbook: $($script:HandbookPath) does not exist yet ($handbookFile)."; exit 0 }
    Write-Output "Team handbook: $($where.Folder)/$($script:HandbookPath)"
    Write-Output ""
    Write-Output $handbookText
    exit 0
}

# ---------------------------------------------------------------- the product
$want = $Product.Trim().ToLowerInvariant()
$wantSlug = ConvertTo-NoteSlug $Product
$products = @(Get-SettingsItems $where "products" | Where-Object { -not (& $prop $_ "archived") })
$p = $products | Where-Object {
    ([string]$_.name).ToLowerInvariant() -eq $want -or ([string]$_.slug) -eq $wantSlug -or
    @(& $prop $_ "alsoCalled" | Where-Object { ([string]$_).ToLowerInvariant() -eq $want }).Count -gt 0
} | Select-Object -First 1

$slug = if ($p) { [string]$p.slug } else { $wantSlug }
$title = if ($p) { [string]$p.name } else { $Product.Trim() }
$noteRel = "products/$slug.md"
$noteFile = Join-Path $where.ProductsDir "$slug.md"
$sources = @()
$out = [System.Collections.Generic.List[string]]::new()

$out.Add("# Knowledge: $title")
$out.Add("")
if ($p) {
    $sources += "settings/products.json"
    $out.Add("## Product (Workshop Settings, settings/products.json)")
    $out.Add("")
    $rows = @(
        @("Also called", (& $names (& $prop $p "alsoCalled"))),
        @("Repos", (& $names (& $prop $p "repos"))),
        @("Area paths", (& $names (& $prop $p "areas"))),
        @("Change order", (@(& $prop $p "changeOrder" | Where-Object { $_ }) -join ", then ")),
        @("Usually change together", (@(& $prop $p "together" | Where-Object { $_ }) -join "; ")),
        @("Entry points", (& $names (& $prop $p "entryPoints"))),
        @("External systems", (& $names (& $prop $p "external"))),
        @("Business processes", (& $names (& $prop $p "processes"))),
        @("Product docs", [string](& $prop $p "docsFolder"))
    )
    foreach ($r in $rows) { if ($r[1]) { $out.Add("- $($r[0]): $($r[1])") } }
    $out.Add("")

    # Owners: active people whose Owns names the product, another name, a repo (or its last folder) or an area path.
    $terms = @($p.name) + @(& $prop $p "alsoCalled") + @(& $prop $p "repos") | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLowerInvariant().Replace('\', '/').TrimEnd('/') }
    $terms += @(& $prop $p "repos" | Where-Object { $_ } | ForEach-Object { (([string]$_).Replace('\', '/').TrimEnd('/') -split '/')[-1].ToLowerInvariant() })
    $areas = @(& $prop $p "areas" | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLowerInvariant().Replace('\', '/').TrimEnd('/') })
    $owners = @()
    foreach ($person in @(Get-SettingsItems $where "people" 2)) {
        if ((& $prop $person "kind") -eq "group" -or (& $prop $person "archived")) { continue }
        $hits = @(& $prop $person "owns" | Where-Object { $_ } | Where-Object {
            $w = ([string]$_).ToLowerInvariant().Replace('\', '/').TrimEnd('/')
            ($terms -contains $w) -or @($areas | Where-Object { $_ -eq $w -or $_.StartsWith("$w/") }).Count -gt 0
        })
        if ($hits.Count) {
            $role = [string](& $prop $person "role")
            $owners += "- $($person.name)$(if ($role) { ", $role" }) (owns $($hits -join ', '))"
        }
    }
    $out.Add("## Owners (Workshop People)")
    $out.Add("")
    if ($owners.Count) { $sources += "settings/people.json"; foreach ($o in $owners) { $out.Add($o) } } else { $out.Add("No owner named in People yet.") }
    $out.Add("")

    # Glossary: this product's words, then the ones for any product.
    $words = @(Get-SettingsItems $where "glossary")
    $ids = @($products | ForEach-Object { $_.id })
    $mine = @($words | Where-Object { (& $prop $_ "productId") -eq $p.id }) + @($words | Where-Object { -not (& $prop $_ "productId") -or $ids -notcontains (& $prop $_ "productId") })
    if ($mine.Count) {
        $sources += "settings/glossary.json"
        $out.Add("## Glossary (Workshop Settings, settings/glossary.json)")
        $out.Add("")
        foreach ($w in $mine) {
            $at = [string](& $prop $w "where")
            $out.Add("- $($w.term) = ``$($w.code)``$(if ($at) { " ($at)" })")
        }
        $out.Add("")
    }
} else {
    $out.Add("Not a product in Workshop Settings (Knowledge, Products). Check the repo map's product names.")
    $out.Add("")
}

$noteText = Get-NoteBody $noteFile
$out.Add("## Product note ($($where.Folder)/$noteRel)")
$out.Add("")
if ($null -eq $noteText) { $out.Add("No product note yet ($noteFile).") } else { $sources += "$($where.Folder)/$noteRel"; foreach ($l in ($noteText -split "`n")) { $out.Add($l) } }
$out.Add("")

$out.Add("## Team handbook ($($where.Folder)/$($script:HandbookPath))")
$out.Add("")
if ($null -eq $handbookText) { $out.Add("No team handbook yet.") }
else {
    $sources += "$($where.Folder)/$($script:HandbookPath)"
    $room = $MaxLines - $out.Count - 3
    $hb = @($handbookText -split "`n")
    if ($hb.Count -gt $room) {
        foreach ($l in ($hb | Select-Object -First ([Math]::Max(0, $room)))) { $out.Add($l) }
        $out.Add("")
        $out.Add("(Handbook cut here to keep this short. Get-Knowledge.ps1 -Handbook prints all of it.)")
    } else { foreach ($l in $hb) { $out.Add($l) } }
}
$out.Add("")
$out.Add("Sources: $($sources -join ', ')")
Write-Output ($out -join "`n")
