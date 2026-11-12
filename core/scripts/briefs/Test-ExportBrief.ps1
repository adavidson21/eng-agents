<#
.SYNOPSIS
  Self-test for Export-Brief.ps1. Writes only to a temp folder.
  Run: pwsh -NoProfile -File core/scripts/briefs/Test-ExportBrief.ps1   (also works in Windows PowerShell 5.1)
#>
$ErrorActionPreference = "Stop"

$failed = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = "") {
    if ($Ok) { Write-Output "ok   $Name" } else { Write-Output "FAIL $Name $Detail"; $script:failed++ }
}

$ps = (Get-Process -Id $PID).Path
$export = Join-Path $PSScriptRoot "Export-Brief.ps1"
function Run([string[]]$Arguments) {
    $ErrorActionPreference = "Continue"
    $out = & $ps -NoProfile -ExecutionPolicy Bypass -File $export @Arguments 2>&1 | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ("brief-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$enc = New-Object System.Text.UTF8Encoding($false)
try {
    $md = @'
# Spike findings: Add bulk export to the reports page

Date: 2026-11-12
Asked by: CEO
Size: M
Effort: 3 to 5 weeks
Confidence: Medium
Lenses: business, engineering, leadership
Default lens: leadership

<!-- a comment that must not show -->

## The ask

> How hard would it be to let customers export all reports at once?

We read this as a zip of every report the user can see.

## Short answer

### For business

Customers get one-click export in about a month.

### For engineering

Reuse the `ExportJob` queue; the risk is **memory** on large tenants.

### For leadership

Recommend option A. Decision: approve 4 weeks.

## Questions for the requester

- Which customers asked for this?

## Options

### For engineering

| Option | How it works | Effort (S/M/L) |
|---|---|---|
| A | Queue + zip <script>alert(1)</script> | M |
| B | Stream | L |

### For leadership

- **A:** cheaper, slower for huge tenants

## Sources

- [design doc](https://example.com/doc) and [bad](javascript:alert(1))
'@
    $file = Join-Path $root "findings.md"
    [IO.File]::WriteAllText($file, ($md -replace "\r\n", "`n"), $enc)

    $r = Run @("-Path", $file)
    $html = Join-Path $root "brief.html"
    $page = if (Test-Path $html) { [IO.File]::ReadAllText($html) } else { "" }
    Check "writes brief.html next to findings.md" ($r.Code -eq 0 -and $page -match '^<!DOCTYPE html>') $r.Out
    Check "title without the prefix" ($page -match '<h1>Add bulk export to the reports page</h1>')
    Check "meta chips" ($page -match '<b>Size</b> M' -and $page -match '<b>Effort</b> 3 to 5 weeks' -and $page -match '<b>Confidence</b> Medium')
    Check "three lens tabs" ($page -match 'for="l-business"' -and $page -match 'for="l-engineering"' -and $page -match 'for="l-leadership"')
    Check "default lens opens" ($page -match 'id="l-leadership" class="lens-radio" checked')
    Check "lens blocks wrapped" ($page -match '<div class="lens lens-business"><p>Customers get one-click export' -and $page -match '<div class="lens lens-engineering">')
    Check "sections with only some lenses are marked" ($page -match 'class="section lensed has-engineering has-leadership"><h2>Options')
    Check "shared sections are not lensed" ($page -match 'class="section"><h2>Questions for the requester')
    Check "no comments" ($page -notmatch 'must not show')
    Check "html in the text is escaped" ($page -notmatch '<script>' -and $page -match '&lt;script&gt;')
    Check "safe links only" ($page -match '<a href="https://example.com/doc">design doc</a>' -and $page -notmatch 'href="javascript')
    Check "inline code and bold" ($page -match '<code>ExportJob</code>' -and $page -match '<strong>memory</strong>')
    Check "table" ($page -match '<th>Option</th>' -and $page -match '<td>Stream</td>')
    Check "blockquote" ($page -match '<blockquote><p>How hard would it be')
    Check "no web requests" ($page -notmatch '(src|href)="https?://(?!example\.com)' -and $page -notmatch '@import' -and $page -notmatch '<script')
    Check "ascii-safe output is UTF-8 without BOM" ([IO.File]::ReadAllBytes($html)[0] -eq 0x3C)

    $out = Join-Path $root "custom.html"
    $r = Run @("-Path", $file, "-Lens", "business", "-Out", $out)
    $page = if (Test-Path $out) { [IO.File]::ReadAllText($out) } else { "" }
    Check "-Lens and -Out" ($r.Code -eq 0 -and $page -match 'id="l-business" class="lens-radio" checked') $r.Out

    $r = Run @("-Path", $file, "-Lens", "sales", "-Out", $out)
    $page = [IO.File]::ReadAllText($out)
    Check "unknown lens falls back to the default" ($r.Out -match "not in this brief" -and $page -match 'id="l-leadership" class="lens-radio" checked') $r.Out

    $old = Join-Path $root "old.md"
    [IO.File]::WriteAllText($old, "# Spike findings: Old one`n`nDate: 2026-01-01`n`n## Short answer`n`nIt works.`n`n## Options`n`n### For engineering`n`nA thing.`n", $enc)
    $r = Run @("-Path", $old, "-Out", $out)
    $page = [IO.File]::ReadAllText($out)
    Check "older findings without Lenses: no switch, still a page" ($r.Code -eq 0 -and $page -notmatch 'class="switch"' -and $page -match '<p>It works.</p>' -and $page -match '<h3>For Engineering</h3>') $r.Out

    $r = Run @("-Path", (Join-Path $root "missing.md"))
    Check "missing file: exit 1" ($r.Code -eq 1 -and $r.Out -match "No file") $r.Out
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failed) { Write-Output "$failed failed."; exit 1 }
Write-Output "Export-Brief: all checks passed."
exit 0
