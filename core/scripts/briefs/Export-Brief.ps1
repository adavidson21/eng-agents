<#
.SYNOPSIS
  Turns a spike's findings.md into one self-contained HTML page to share: no web requests, no external files,
  works when opened from email, Teams, SharePoint or a download, and prints cleanly (Save as PDF).

.DESCRIPTION
  If findings.md has a "Lenses:" line, the page gets a Business / Engineering / Leadership switch. A
  "### For <lens>" block shows only in that lens; everything else shows in every lens. The switch is plain
  HTML and CSS (no script), so it still works where scripts are blocked. Printing prints the open lens.

  Run: pwsh -NoProfile -File Export-Brief.ps1 -Path .work/spike-x/findings.md [-Lens leadership] [-Out brief.html]
  Writes brief.html next to findings.md unless -Out is given. Prints the path written.
  Works in Windows PowerShell 5.1 and PowerShell 7. Keep this file ASCII (5.1 reads it without a BOM).
#>
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$Lens = "",
    [string]$Out = ""
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$Known = @("business", "engineering", "leadership")

function ConvertTo-Html([string]$s) {
    return $s.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace('"', "&quot;")
}

# Inline Markdown: code, bold, italic, links. Text is escaped first; code spans are kept out of the rest.
function ConvertFrom-Inline([string]$s) {
    $codes = New-Object System.Collections.Generic.List[string]
    $s = [regex]::Replace($s, '`([^`]+)`', {
        param($m) $codes.Add("<code>" + (ConvertTo-Html $m.Groups[1].Value) + "</code>"); return ([string][char]1) + [string]($codes.Count - 1) + ([string][char]2)
    })
    $s = ConvertTo-Html $s
    $s = [regex]::Replace($s, '\[([^\]]+)\]\(([^)\s]+)\)', {
        param($m)
        $url = $m.Groups[2].Value
        if ($url -match '^(?i)(https?:|mailto:|#|\./|\.\./|[a-z0-9_./-]+$)' -and $url -notmatch '^(?i)(javascript|data|vbscript):') {
            return '<a href="' + $url + '">' + $m.Groups[1].Value + '</a>'
        }
        return $m.Groups[1].Value
    })
    $s = [regex]::Replace($s, '\*\*(.+?)\*\*', '<strong>$1</strong>')
    $s = [regex]::Replace($s, '(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])', '<em>$1</em>')
    $s = [regex]::Replace($s, ([string][char]1) + '(\d+)' + ([string][char]2), { param($m) $codes[[int]$m.Groups[1].Value] })
    return $s
}

function Split-Row([string]$line) {
    $t = $line.Trim()
    if ($t.StartsWith("|")) { $t = $t.Substring(1) }
    if ($t.EndsWith("|")) { $t = $t.Substring(0, $t.Length - 1) }
    return @($t -split '\|' | ForEach-Object { $_.Trim() })
}

# Block Markdown for one run of lines (a section body or a lens block).
function ConvertFrom-Blocks([string[]]$lines) {
    $sb = New-Object System.Text.StringBuilder
    $i = 0
    $n = $lines.Count
    while ($i -lt $n) {
        $line = $lines[$i]
        if ($line.Trim() -eq "") { $i++; continue }
        if ($line -match '^\s*```(.*)$') {
            $lang = $Matches[1].Trim()
            $buf = New-Object System.Collections.Generic.List[string]
            $i++
            while ($i -lt $n -and $lines[$i] -notmatch '^\s*```\s*$') { $buf.Add($lines[$i]); $i++ }
            $i++
            $cls = if ($lang) { ' class="lang-' + (ConvertTo-Html $lang) + '"' } else { "" }
            [void]$sb.Append("<pre><code$cls>" + (ConvertTo-Html ($buf -join "`n")) + "</code></pre>`n")
            continue
        }
        if ($line -match '^(#{3,6})\s+(.+?)\s*#*\s*$') {
            $lvl = [Math]::Min($Matches[1].Length, 4)
            [void]$sb.Append("<h$lvl>" + (ConvertFrom-Inline $Matches[2]) + "</h$lvl>`n"); $i++; continue
        }
        if ($line -match '^\s*(-{3,}|\*{3,})\s*$') { [void]$sb.Append("<hr>`n"); $i++; continue }
        if ($line -match '^\s*\|' -and $i + 1 -lt $n -and $lines[$i + 1] -match '^\s*\|?\s*:?-{2,}') {
            $head = Split-Row $line
            [void]$sb.Append("<div class=""table""><table><thead><tr>")
            foreach ($c in $head) { [void]$sb.Append("<th>" + (ConvertFrom-Inline $c) + "</th>") }
            [void]$sb.Append("</tr></thead><tbody>")
            $i += 2
            while ($i -lt $n -and $lines[$i] -match '^\s*\|') {
                $cells = Split-Row $lines[$i]
                [void]$sb.Append("<tr>")
                for ($c = 0; $c -lt $head.Count; $c++) {
                    $v = if ($c -lt $cells.Count) { $cells[$c] } else { "" }
                    [void]$sb.Append("<td>" + (ConvertFrom-Inline $v) + "</td>")
                }
                [void]$sb.Append("</tr>")
                $i++
            }
            [void]$sb.Append("</tbody></table></div>`n")
            continue
        }
        if ($line -match '^\s*>') {
            $buf = New-Object System.Collections.Generic.List[string]
            while ($i -lt $n -and $lines[$i] -match '^\s*>\s?(.*)$') { $buf.Add($Matches[1]); $i++ }
            [void]$sb.Append("<blockquote>" + (ConvertFrom-Blocks $buf.ToArray()) + "</blockquote>`n")
            continue
        }
        if ($line -match '^(\s*)([-*+]|\d+[.)])\s+') {
            $ordered = $Matches[2] -match '^\d'
            $tag = if ($ordered) { "ol" } else { "ul" }
            [void]$sb.Append("<$tag>")
            while ($i -lt $n -and $lines[$i] -match '^(\s*)([-*+]|\d+[.)])\s+(.*)$') {
                $indent = $Matches[1].Length
                $text = $Matches[3]
                $i++
                while ($i -lt $n -and $lines[$i].Trim() -ne "" -and $lines[$i] -match '^\s{2,}\S' -and $lines[$i] -notmatch '^\s*([-*+]|\d+[.)])\s+') {
                    $text += " " + $lines[$i].Trim(); $i++
                }
                $cls = if ($indent -ge 2) { ' class="sub"' } else { "" }
                if ($text -match '^\[( |x|X)\]\s+(.*)$') {
                    $box = if ($Matches[1] -eq " ") { "&#9744; " } else { "&#9745; " }
                    $text = $Matches[2]
                    [void]$sb.Append("<li$cls>$box" + (ConvertFrom-Inline $text) + "</li>")
                } else {
                    [void]$sb.Append("<li$cls>" + (ConvertFrom-Inline $text) + "</li>")
                }
            }
            [void]$sb.Append("</$tag>`n")
            continue
        }
        $buf = New-Object System.Collections.Generic.List[string]
        while ($i -lt $n -and $lines[$i].Trim() -ne "" -and $lines[$i] -notmatch '^\s*(```|#{1,6}\s|>|\||([-*+]|\d+[.)])\s+)') {
            $buf.Add($lines[$i].Trim()); $i++
        }
        if ($buf.Count -eq 0) { $buf.Add($lines[$i].Trim()); $i++ }
        [void]$sb.Append("<p>" + (ConvertFrom-Inline ($buf -join " ")) + "</p>`n")
    }
    return $sb.ToString()
}

# ---- Read and parse findings.md --------------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Write-Output "No file at $Path."; exit 1 }
$full = (Resolve-Path -LiteralPath $Path).Path
$text = [IO.File]::ReadAllText($full, [Text.Encoding]::UTF8)
$text = [regex]::Replace($text, '(?s)<!--.*?-->', '')
$lines = @($text -split "\r?\n")

$title = "Spike findings"
$meta = [ordered]@{}
$sections = New-Object System.Collections.Generic.List[object]
$cur = $null
$preamble = New-Object System.Collections.Generic.List[string]
foreach ($line in $lines) {
    if ($line -match '^#\s+(.+?)\s*$' -and -not $cur -and $title -eq "Spike findings") {
        $title = ($Matches[1] -replace '^Spike findings:\s*', '').Trim(); continue
    }
    if ($line -match '^##\s+(.+?)\s*$') {
        $cur = [pscustomobject]@{ Title = $Matches[1]; Lines = (New-Object System.Collections.Generic.List[string]) }
        $sections.Add($cur); continue
    }
    if (-not $cur) {
        if ($line -match '^([A-Z][A-Za-z ]{1,24}):\s*(.+?)\s*$') { $meta[$Matches[1]] = $Matches[2] }
        elseif ($line.Trim()) { $preamble.Add($line) }
        continue
    }
    $cur.Lines.Add($line)
}

$lenses = @()
if ($meta.Contains("Lenses")) {
    $lenses = @(($meta["Lenses"] -split '[,\s]+') | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $Known -contains $_ })
}
$want = $Lens.Trim().ToLowerInvariant()
$default = if ($meta.Contains("Default lens")) { $meta["Default lens"].Trim().ToLowerInvariant() } else { "" }
$open = ""
if ($lenses.Count -gt 0) {
    if ($lenses -contains $want) { $open = $want }
    elseif ($lenses -contains $default) { $open = $default }
    elseif ($lenses -contains "engineering") { $open = "engineering" }
    else { $open = $lenses[0] }
    if ($want -and $want -ne $open) { Write-Output "Lens '$Lens' is not in this brief ($($lenses -join ', ')). Opening $open." }
}

# A section body split into shared lines and "### For <lens>" blocks, in order.
function Split-Lenses($body) {
    $parts = New-Object System.Collections.Generic.List[object]
    $part = [pscustomobject]@{ Lens = ""; Lines = (New-Object System.Collections.Generic.List[string]) }
    $parts.Add($part)
    $fence = $false
    foreach ($l in $body) {
        if ($l -match '^\s*```') { $fence = -not $fence }
        if (-not $fence -and $l -match '^###\s+For\s+(business|engineering|leadership)\b.*$') {
            $part = [pscustomobject]@{ Lens = $Matches[1].ToLowerInvariant(); Lines = (New-Object System.Collections.Generic.List[string]) }
            $parts.Add($part); continue
        }
        if (-not $fence -and $part.Lens -and $l -match '^#{1,3}\s') {
            $part = [pscustomobject]@{ Lens = ""; Lines = (New-Object System.Collections.Generic.List[string]) }
            $parts.Add($part)
        }
        $part.Lines.Add($l)
    }
    return $parts
}

$body = New-Object System.Text.StringBuilder
if ($preamble.Count -gt 0) { [void]$body.Append((ConvertFrom-Blocks $preamble.ToArray())) }
foreach ($s in $sections) {
    $parts = Split-Lenses $s.Lines
    $has = @($parts | Where-Object { $_.Lens -and ($_.Lines -join "").Trim() } | ForEach-Object { $_.Lens } | Select-Object -Unique)
    $shared = @($parts | Where-Object { -not $_.Lens -and ($_.Lines -join "").Trim() }).Count -gt 0
    $cls = "section"
    if ($lenses.Count -gt 0 -and -not $shared -and $has.Count -gt 0) {
        $cls += " lensed" + (($has | ForEach-Object { " has-$_" }) -join "")
    }
    [void]$body.Append("<section class=""$cls""><h2>" + (ConvertFrom-Inline $s.Title) + "</h2>`n")
    foreach ($p in $parts) {
        $html = ConvertFrom-Blocks $p.Lines.ToArray()
        if (-not $html.Trim()) { continue }
        if ($p.Lens -and $lenses.Count -gt 0) {
            [void]$body.Append("<div class=""lens lens-$($p.Lens)"">$html</div>`n")
        } elseif ($p.Lens) {
            $name = (Get-Culture).TextInfo.ToTitleCase($p.Lens)
            [void]$body.Append("<h3>For $name</h3>`n$html")
        } else {
            [void]$body.Append($html)
        }
    }
    [void]$body.Append("</section>`n")
}

# ---- Page ------------------------------------------------------------------------------------------------

$chips = New-Object System.Text.StringBuilder
foreach ($k in @("Size", "Effort", "Confidence", "Asked by", "Date")) {
    if ($meta.Contains($k) -and $meta[$k] -and $meta[$k] -notmatch '^<.*>$') {
        [void]$chips.Append("<span class=""chip""><b>" + (ConvertTo-Html $k) + "</b> " + (ConvertTo-Html $meta[$k]) + "</span>")
    }
}

$radios = ""; $switch = ""; $lensCss = ""
if ($lenses.Count -gt 0) {
    $r = New-Object System.Text.StringBuilder
    $sw = New-Object System.Text.StringBuilder
    $css = New-Object System.Text.StringBuilder
    [void]$sw.Append("<nav class=""switch"" aria-label=""Read as"">")
    foreach ($l in $lenses) {
        $checked = if ($l -eq $open) { " checked" } else { "" }
        $name = (Get-Culture).TextInfo.ToTitleCase($l)
        [void]$r.Append("<input type=""radio"" name=""lens"" id=""l-$l"" class=""lens-radio""$checked>")
        [void]$sw.Append("<label for=""l-$l"" class=""tab-$l"">$name</label>")
        [void]$css.Append("#l-$l`:checked ~ .page .lens:not(.lens-$l), #l-$l`:checked ~ .page section.lensed:not(.has-$l) { display: none; }`n")
        [void]$css.Append("#l-$l`:checked ~ .page .tab-$l { background: var(--ink); color: var(--paper); border-color: var(--ink); }`n")
        [void]$css.Append("#l-$l`:focus-visible ~ .page .tab-$l { outline: 2px solid var(--accent); outline-offset: 2px; }`n")
    }
    [void]$sw.Append("</nav>")
    $radios = $r.ToString(); $switch = $sw.ToString(); $lensCss = $css.ToString()
}

$generated = (Get-Date).ToString("yyyy-MM-dd")
$page = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="generator" content="eng-agents Export-Brief">
<title>$(ConvertTo-Html $title)</title>
<style>
:root { --ink: #1c1f24; --muted: #5b6270; --line: #dfe2e7; --paper: #ffffff; --wash: #f5f6f8; --accent: #2f5bd3; }
@media (prefers-color-scheme: dark) { :root { --ink: #e7e9ee; --muted: #a2a8b4; --line: #343a45; --paper: #16191e; --wash: #1e2229; --accent: #8aa8ff; } }
* { box-sizing: border-box; }
html { background: var(--wash); }
body { margin: 0; color: var(--ink); font: 16px/1.6 -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; }
.lens-radio { position: absolute; opacity: 0; pointer-events: none; }
.page { max-width: 820px; margin: 32px auto; padding: 40px 48px; background: var(--paper); border: 1px solid var(--line); border-radius: 10px; }
header { border-bottom: 1px solid var(--line); padding-bottom: 20px; margin-bottom: 8px; }
.kicker { color: var(--muted); font-size: 13px; margin: 0 0 4px; }
h1 { font-size: 28px; line-height: 1.25; margin: 0 0 14px; }
.chips { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 16px; }
.chip { font-size: 13px; padding: 3px 10px; border: 1px solid var(--line); border-radius: 999px; background: var(--wash); }
.chip b { font-weight: 600; color: var(--muted); }
.switch { display: inline-flex; gap: 4px; }
.switch label { cursor: pointer; font-size: 14px; padding: 6px 14px; border: 1px solid var(--line); border-radius: 6px; user-select: none; }
.switch label:hover { border-color: var(--muted); }
h2 { font-size: 19px; margin: 28px 0 8px; }
h3 { font-size: 16px; margin: 18px 0 6px; }
h4 { font-size: 15px; margin: 14px 0 4px; }
p, ul, ol { margin: 0 0 12px; }
li { margin: 2px 0; }
li.sub { margin-left: 20px; }
a { color: var(--accent); }
code { font: 13.5px/1.4 ui-monospace, "Cascadia Mono", Consolas, Menlo, monospace; background: var(--wash); padding: 1px 5px; border-radius: 4px; }
pre { background: var(--wash); border: 1px solid var(--line); border-radius: 6px; padding: 12px 14px; overflow-x: auto; }
pre code { background: none; padding: 0; }
blockquote { margin: 0 0 12px; padding: 4px 16px; border-left: 3px solid var(--line); color: var(--muted); }
.table { overflow-x: auto; margin: 0 0 12px; }
table { border-collapse: collapse; width: 100%; font-size: 14.5px; }
th, td { text-align: left; vertical-align: top; padding: 7px 10px; border-bottom: 1px solid var(--line); }
th { font-weight: 600; background: var(--wash); }
hr { border: 0; border-top: 1px solid var(--line); margin: 20px 0; }
footer { margin-top: 32px; padding-top: 12px; border-top: 1px solid var(--line); color: var(--muted); font-size: 12.5px; }
$lensCss
@media (max-width: 640px) { .page { margin: 0; padding: 24px 18px; border: 0; border-radius: 0; } }
@media print {
  :root { --ink: #000; --muted: #444; --line: #ccc; --paper: #fff; --wash: #f4f4f4; --accent: #000; }
  html { background: #fff; } .page { margin: 0; padding: 0; border: 0; max-width: none; }
  .switch { display: none; }
  section, tr, pre { break-inside: avoid; } a { text-decoration: none; }
}
</style>
</head>
<body>
$radios
<div class="page">
<header>
<p class="kicker">Spike findings</p>
<h1>$(ConvertTo-Html $title)</h1>
<div class="chips">$($chips.ToString())</div>
$switch
</header>
<main>
$($body.ToString())
</main>
<footer>Generated $generated from findings.md. A first-pass investigation: check the open questions before treating estimates as commitments.</footer>
</div>
</body>
</html>
"@

if (-not $Out) { $Out = Join-Path (Split-Path -Parent $full) "brief.html" }
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($Out, ($page -replace "\r\n", "`n"), $enc)
Write-Output "Wrote $Out"
