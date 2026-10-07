<#
.SYNOPSIS
    Checks every Mermaid block in a markdown file and renders each one to SVG.

.DESCRIPTION
    1. Finds every ```mermaid block in -Path.
    2. Runs quick static checks on each block (allowed diagram type, balanced quotes,
       no newer syntax that older renderers reject).
    3. If mermaid-cli (mmdc) is installed, renders each block to <OutDir>\block-NN.svg.
       A block that fails to render has a syntax error. The SVGs can also be pasted
       into a doc editor that does not render Mermaid.

    The browser mmdc uses is chosen in this order:
      1. -BrowserPath
      2. "mermaid": { "browserPath": "..." } in ~/.config/eng-agents/config.json
      3. An installed Microsoft Edge or Google Chrome
      4. The browser puppeteer downloaded when mermaid-cli was installed

    The LAST line of output is always one of:
      RESULT: PASS <n> of <n>
      RESULT: FAIL <failed> of <n>
      RESULT: SKIPPED render (mmdc not found). Static checks: PASS <n> of <n>
    Exit code: 0 pass, 1 fail, 2 skipped.

    Install mermaid-cli once (downloads its own Chromium unless one is set above):
      npm install -g @mermaid-js/mermaid-cli

.EXAMPLE
    .\Test-Mermaid.ps1 -Path .work\tsd-orders\tsd.md

.EXAMPLE
    .\Test-Mermaid.ps1 -Path .work\tsd-orders\tsd.md -BrowserPath "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    # Where block files and SVGs are written. Default: a "render" folder next to -Path.
    [string]$OutDir,

    # Chrome or Edge executable for mmdc. Autodetected when empty.
    [string]$BrowserPath,

    [string]$ConfigPath = (Join-Path $(if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }) ".config/eng-agents/config.json")
)

$ErrorActionPreference = "Stop"

# Diagram types every common Mermaid renderer supports. Newer types (C4, block, architecture)
# are left out on purpose: many doc editors bundle an older Mermaid that cannot draw them.
$allowedTypes = @("flowchart", "graph", "sequenceDiagram", "erDiagram", "classDiagram", "stateDiagram-v2", "stateDiagram")

function Write-Result {
    param([string]$Text, [int]$Code)
    Write-Output $Text
    exit $Code
}

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Write-Result "RESULT: FAIL file not found: $Path" 1
}
$fullPath = (Resolve-Path -LiteralPath $Path).Path
if (-not $OutDir) { $OutDir = Join-Path (Split-Path -Parent $fullPath) "render" }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

# ---------------------------------------------------------------- find blocks

$lines = [System.IO.File]::ReadAllLines($fullPath)
$blocks = New-Object System.Collections.Generic.List[object]
$heading = "(top)"
$inBlock = $false
$fence = ""
$start = 0
$body = $null

for ($i = 0; $i -lt $lines.Length; $i++) {
    $line = $lines[$i]
    if (-not $inBlock) {
        $h = [regex]::Match($line, '^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$')
        if ($h.Success) { $heading = $h.Groups[1].Value; continue }
        $m = [regex]::Match($line, '^\s*(`{3,}|~{3,})\s*mermaid\s*$')
        if ($m.Success) {
            $inBlock = $true
            $fence = $m.Groups[1].Value
            $start = $i + 1
            $body = New-Object System.Collections.Generic.List[string]
        }
        continue
    }
    if ($line.Trim() -eq $fence) {
        $blocks.Add([pscustomobject]@{ Number = $blocks.Count + 1; Line = $start; Heading = $heading; Text = ($body -join "`n") })
        $inBlock = $false
        continue
    }
    $body.Add($line)
}
if ($inBlock) {
    Write-Output "FAIL  block $($blocks.Count + 1)  line $start  `"$heading`""
    Write-Output "      The mermaid block is never closed. Add a closing $fence line."
    Write-Result "RESULT: FAIL 1 of $($blocks.Count + 1)" 1
}
if ($blocks.Count -eq 0) {
    Write-Result "RESULT: FAIL no mermaid blocks found in $Path" 1
}

Write-Output "Checking $($blocks.Count) Mermaid blocks in $Path"

# ---------------------------------------------------------------- static checks

function Get-StaticProblems {
    param([string]$Text)
    $problems = @()
    $codeLines = @($Text -split "`n" | Where-Object { $_.Trim() -ne "" -and -not $_.Trim().StartsWith("%%") })
    if ($codeLines.Count -eq 0) { return @("The block is empty.") }

    $type = ($codeLines[0].Trim() -split '\s+')[0]
    if ($allowedTypes -notcontains $type) {
        $problems += "Diagram type '$type' is not allowed. Use one of: $($allowedTypes -join ', ')."
    }
    for ($j = 0; $j -lt $codeLines.Count; $j++) {
        $l = $codeLines[$j]
        if ((([regex]::Matches($l, '"')).Count % 2) -ne 0) {
            $problems += "Unbalanced double quotes: $($l.Trim())"
        }
        if ($l -match '@\{') {
            $problems += "The @{ ... } shape syntax needs Mermaid 11.3 or later. Use the classic shapes from the cookbook: $($l.Trim())"
        }
    }
    return $problems
}

# ---------------------------------------------------------------- find mmdc and a browser

$mmdc = Get-Command mmdc -ErrorAction SilentlyContinue | Select-Object -First 1

function Find-Browser {
    if ($BrowserPath) {
        if (Test-Path -LiteralPath $BrowserPath) { return $BrowserPath }
        Write-Output "WARN  -BrowserPath not found: $BrowserPath"
    }
    if (Test-Path -LiteralPath $ConfigPath) {
        try {
            $cfg = [System.IO.File]::ReadAllText($ConfigPath) | ConvertFrom-Json
            if ($cfg.PSObject.Properties["mermaid"] -and $cfg.mermaid.browserPath) {
                if (Test-Path -LiteralPath $cfg.mermaid.browserPath) { return $cfg.mermaid.browserPath }
                Write-Output "WARN  mermaid.browserPath in config.json not found: $($cfg.mermaid.browserPath)"
            }
        }
        catch { Write-Output "WARN  could not read $ConfigPath. Ignoring it." }
    }
    $candidates = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
        "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    )
    foreach ($c in $candidates) {
        if ($c -and -not $c.StartsWith("\") -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

$puppeteerConfig = $null
if ($mmdc) {
    $browser = Find-Browser
    $pc = [ordered]@{}
    if ($browser) {
        $pc["executablePath"] = $browser
        # mmdc defaults to the old headless mode, which only puppeteer's own headless shell has.
        # Installed Edge and Chrome need the new headless mode.
        $pc["headless"] = $true
    }
    # Linux containers usually run as root, where Chromium refuses to start without this.
    if ($PSVersionTable.PSEdition -eq "Core" -and $IsLinux) { $pc["args"] = @("--no-sandbox") }
    $puppeteerConfig = Join-Path $OutDir "puppeteer-config.json"
    [System.IO.File]::WriteAllText($puppeteerConfig, ($pc | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
    $browserNote = if ($browser) { $browser } else { "puppeteer's downloaded browser" }
    Write-Output "Rendering with $($mmdc.Source) using $browserNote"
}

# ---------------------------------------------------------------- check each block

$failed = 0
$enc = New-Object System.Text.UTF8Encoding($false)
foreach ($b in $blocks) {
    $label = "block $($b.Number)  line $($b.Line)  `"$($b.Heading)`""
    $problems = @(Get-StaticProblems $b.Text)

    if ($problems.Count -eq 0 -and $mmdc) {
        $name = "block-{0:D2}" -f $b.Number
        $in = Join-Path $OutDir "$name.mmd"
        $out = Join-Path $OutDir "$name.svg"
        [System.IO.File]::WriteAllText($in, $b.Text + "`n", $enc)
        if (Test-Path $out) { Remove-Item $out -Force }

        $prev = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $output = & $mmdc.Source -i $in -o $out -p $puppeteerConfig -b white -q 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE
        $ErrorActionPreference = $prev

        if ($code -ne 0 -or -not (Test-Path $out)) {
            $msg = @($output | Where-Object {
                    $_.Trim() -ne "" -and
                    $_ -notmatch '^\s+at ' -and
                    $_ -notmatch 'RemoteException' -and
                    $_ -notmatch '\((https?|file):'
                } | Select-Object -First 5)
            if ($msg.Count -eq 0) { $msg = @("mmdc failed with exit code $code and no message.") }
            # Point at the line in the markdown file, not just the line inside the block.
            $msg = @($msg | ForEach-Object {
                    $pm = [regex]::Match($_, 'on line (\d+)')
                    if ($pm.Success) { "$_ (file line $($b.Line + [int]$pm.Groups[1].Value))" } else { $_ }
                })
            $problems += $msg
        }
    }

    if ($problems.Count -eq 0) {
        if ($mmdc) { Write-Output "PASS  $label" } else { Write-Output "PASS  $label  (static checks only, not rendered)" }
    }
    else {
        $failed++
        Write-Output "FAIL  $label"
        foreach ($p in $problems) { Write-Output "      $p" }
    }
}

# ---------------------------------------------------------------- result

$n = $blocks.Count
if ($failed -gt 0) {
    Write-Output "Fix only the FAIL blocks, then run this script again."
    Write-Result "RESULT: FAIL $failed of $n" 1
}
if (-not $mmdc) {
    Write-Output "mermaid-cli is not installed, so blocks were not rendered. Install it with: npm install -g @mermaid-js/mermaid-cli"
    Write-Result "RESULT: SKIPPED render (mmdc not found). Static checks: PASS $n of $n" 2
}
Write-Output "SVGs written to $OutDir"
Write-Result "RESULT: PASS $n of $n" 0
