<#
.SYNOPSIS
    Exports a scope folder's milestones.md as work items: an ADO import file, ADO items, or local items.

.DESCRIPTION
    Reads <Folder>\milestones.md (written by /slice) and does one of:

      -Check   Checks the file's format. Prints FORMAT: lines for each problem (exit 1),
               or a one-line summary (exit 0). Does not need the file to be approved.
      -Csv     Writes <Folder>\backlog.csv for ADO's Import Work Items (Epic, Feature,
               and story rows as a tree with Title 1, Title 2, Title 3 columns).
      -Push    Creates the items in ADO over REST, with parent links. Add -DryRun to
               print what it would create without calling anything.
      -Local   Creates one local work item (.work\L<number>-<name>\) per story with
               New-LocalWorkItem.ps1, for work with no tracker.

    -Csv, -Push, and -Local need milestones.md to say "Status: APPROVED".

    -Push and -Local record each created item in <Folder>\published.md as they go. Running
    the same command again skips items already listed there, so a failed run can be resumed.

    -Push uses the same config.json and PAT environment variable as Get-WorkItem.ps1. It
    picks the connection named with -From, else "default", else the only one. The PAT is
    never written to disk.

    What goes to ADO stays light: a feature's description and its release note, and a
    story's "As a ..." line, context, and acceptance criteria. A story's "Notes for the
    builder" (older files: "Work item") stay local; only -Local items include them.

    Release notes go to their own field. Set it in config.json: "releaseNoteField" (the
    field's reference name, for -Push; a connection may override it) and
    "releaseNoteColumn" (its display name, for the -Csv import). When it is not set, the
    release notes are left out and the output says so.

    The LAST line of output is always the file written (backlog.csv or published.md),
    except for -Check and -DryRun.

.EXAMPLE
    .\Export-Backlog.ps1 -Folder .work\scope-change-request -Check

.EXAMPLE
    .\Export-Backlog.ps1 -Folder .work\scope-change-request -Csv -AreaPath "Proj\Platform" -IterationPath "Proj\Sprint 12"

.EXAMPLE
    .\Export-Backlog.ps1 -Folder .work\scope-change-request -Push -DryRun
#>
[CmdletBinding(DefaultParameterSetName = "Check")]
param(
    [Parameter(Mandatory = $true)]
    [string]$Folder,

    [Parameter(ParameterSetName = "Check")]
    [switch]$Check,

    [Parameter(ParameterSetName = "Csv", Mandatory = $true)]
    [switch]$Csv,

    [Parameter(ParameterSetName = "Push", Mandatory = $true)]
    [switch]$Push,

    [Parameter(ParameterSetName = "Local", Mandatory = $true)]
    [switch]$Local,

    [Parameter(ParameterSetName = "Csv")]
    [Parameter(ParameterSetName = "Push")]
    [string]$AreaPath,

    [Parameter(ParameterSetName = "Csv")]
    [Parameter(ParameterSetName = "Push")]
    [string]$IterationPath,

    [Parameter(ParameterSetName = "Csv")]
    [Parameter(ParameterSetName = "Push")]
    [string]$StoryType = "User Story",

    [Parameter(ParameterSetName = "Push")]
    [switch]$DryRun,

    # Connection name from config.json (Push only).
    [Parameter(ParameterSetName = "Push")]
    [string]$From,

    # ADO project (Push only). Defaults to the connection's "project".
    [Parameter(ParameterSetName = "Push")]
    [string]$Project,

    [string]$ConfigPath = (Join-Path $(if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }) ".config/eng-agents/config.json")
)

$ErrorActionPreference = "Stop"

function Write-Utf8 {
    param([string]$Path, [string]$Content)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

function Get-Prop {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

function Join-Block {
    # Lines to text, without leading or trailing blank lines.
    param($Lines)
    return ((@($Lines) -join "`n").Trim())
}

# ------------------------------------------------------------------ parsing

function Read-Milestones {
    param([string]$Path)

    $errors = New-Object System.Collections.ArrayList
    $raw = [System.IO.File]::ReadAllText($Path)
    $raw = [regex]::Replace($raw, "(?s)<!--.*?-->", "")
    $lines = $raw -split "\r?\n"

    $result = [ordered]@{
        Status        = $null
        EpicTitle     = $null
        EpicId        = $null
        EpicLines     = New-Object System.Collections.ArrayList
        Features      = New-Object System.Collections.ArrayList
        Errors        = $errors
    }

    $section = "top"      # top, epic, feature, release, story, ac, work, ignore
    $feature = $null
    $story = $null
    $inFence = $false

    foreach ($line in $lines) {
        if ($line -match '^\s*```') { $inFence = -not $inFence }
        $isHeading = (-not $inFence) -and ($line -match '^#{1,4}\s')

        if (-not $isHeading -and -not $inFence -and $section -in @("top", "epic") -and $line -match '^Status:\s*(\S+)') {
            if (-not $result.Status) { $result.Status = $Matches[1] }
            continue
        }
        if (-not $isHeading -and -not $inFence -and $section -eq "top" -and $line -match '^Epic:\s*(.*?)\s*$') {
            $v = $Matches[1]
            if ($v -match '^#(\d+)\s*(.*)$') { $result.EpicId = [int]$Matches[1]; $result.EpicTitle = $Matches[2].Trim(); if (-not $result.EpicTitle) { $result.EpicTitle = "#$($result.EpicId)" } }
            else { $result.EpicTitle = $v }
            $section = "epic"
            continue
        }

        if ($isHeading) {
            if ($line -match '^##\s+Feature\s+(\d+)\s*:\s*(.+?)\s*$') {
                $feature = [ordered]@{ Num = [int]$Matches[1]; Title = $Matches[2]; Lines = (New-Object System.Collections.ArrayList); Release = (New-Object System.Collections.ArrayList); HasRelease = $false; Stories = (New-Object System.Collections.ArrayList) }
                [void]$result.Features.Add($feature)
                $story = $null
                $section = "feature"
                continue
            }
            if ($line -match '^###\s+Story\s+(\d+)\.(\d+)\s*:\s*(.+?)\s*$') {
                $fn = [int]$Matches[1]; $sn = [int]$Matches[2]; $title = $Matches[3]
                if (-not $feature) { [void]$errors.Add("Story $fn.$sn is not under a '## Feature <n>: <title>' heading."); $section = "ignore"; continue }
                if ($fn -ne $feature.Num) { [void]$errors.Add("Story $fn.$sn is under Feature $($feature.Num). Number it $($feature.Num).<n>.") }
                $story = [ordered]@{ Ref = "$fn.$sn"; Sub = $sn; Title = $title; Lines = (New-Object System.Collections.ArrayList); Ac = (New-Object System.Collections.ArrayList); Work = (New-Object System.Collections.ArrayList); HasAc = $false }
                [void]$feature.Stories.Add($story)
                $section = "story"
                continue
            }
            if ($line -match '^####\s+Release notes?\s*$' -and $feature -and -not $story) { $feature.HasRelease = $true; $section = "release"; continue }
            if ($line -match '^####\s+Acceptance criteria\s*$' -and $story) { $story.HasAc = $true; $section = "ac"; continue }
            if ($line -match '^####\s+(Notes for the builder|Work item)\s*$' -and $story) { $section = "work"; continue }
            if ($line -match '^####\s' -and $story) {
                # Any other level-4 heading stays part of the story description.
                [void]$story.Lines.Add($line); $section = "story"; continue
            }
            if ($line -match '^#\s') { continue }   # the file title
            if ($line -match '^##\s') {
                # Changes, Coverage, Open questions, or anything else: not exported.
                $feature = $null; $story = $null; $section = "ignore"; continue
            }
            if ($line -match '^###\s' -and $feature -and -not $story) {
                [void]$errors.Add("Heading '$($line.Trim())' under Feature $($feature.Num) is not '### Story $($feature.Num).<n>: <title>'.")
                $section = "ignore"; continue
            }
        }

        switch ($section) {
            "epic"    { [void]$result.EpicLines.Add($line) }
            "feature" { [void]$feature.Lines.Add($line) }
            "release" { [void]$feature.Release.Add($line) }
            "story"   { [void]$story.Lines.Add($line) }
            "ac"      { [void]$story.Ac.Add($line) }
            "work"    { [void]$story.Work.Add($line) }
        }
    }

    # --- checks
    if (-not $result.Status) { [void]$errors.Add("No 'Status:' line near the top.") }
    if (-not $result.EpicTitle) { [void]$errors.Add("No 'Epic: <title>' line before the first feature.") }
    elseif ($result.EpicTitle -match '^<.*>$') { [void]$errors.Add("The Epic line still has the template placeholder.") }
    if ($result.Features.Count -eq 0) { [void]$errors.Add("No '## Feature <n>: <title>' headings.") }

    $expectF = 1
    foreach ($f in $result.Features) {
        if ($f.Num -ne $expectF) { [void]$errors.Add("Feature $($f.Num) is out of order. Expected Feature $expectF. Number features 1, 2, 3 in build order.") }
        $expectF = $f.Num + 1
        if ($f.Title -match '^<.*>$') { [void]$errors.Add("Feature $($f.Num) still has the template title.") }
        if ($f.Stories.Count -eq 0) { [void]$errors.Add("Feature $($f.Num) has no stories. Every feature needs at least one '### Story $($f.Num).<n>: <title>'.") }
        $fdesc = Join-Block $f.Lines
        if (-not $fdesc) { [void]$errors.Add("Feature $($f.Num) has no description. Write two or three sentences under its heading.") }
        elseif ($fdesc -match '(?m)^\s*<[^>]+>\s*$') { [void]$errors.Add("Feature $($f.Num) description still has a template placeholder.") }
        elseif ($fdesc.Length -gt 600) { [void]$errors.Add("Feature $($f.Num) description is $($fdesc.Length) characters. Keep it to two or three sentences (at most 600 characters); design belongs to engineering.") }
        $rn = Join-Block $f.Release
        if (-not $f.HasRelease -or -not $rn) { [void]$errors.Add("Feature $($f.Num) has no '#### Release note' section. Write one or two business-friendly sentences.") }
        elseif ($rn -match '(?m)^\s*<[^>]+>\s*$') { [void]$errors.Add("Feature $($f.Num) release note still has a template placeholder.") }
        elseif ($rn.Length -gt 255) { [void]$errors.Add("Feature $($f.Num) release note is $($rn.Length) characters. Keep it to one or two sentences (at most 255 characters).") }
        $expectS = 1
        foreach ($s in $f.Stories) {
            if ($s.Sub -ne $expectS) { [void]$errors.Add("Story $($s.Ref) is out of order. Expected $($f.Num).$expectS.") }
            $expectS = $s.Sub + 1
            if ($s.Title -match '^<.*>$') { [void]$errors.Add("Story $($s.Ref) still has the template title.") }
            $sdesc = Join-Block $s.Lines
            if (-not $sdesc) { [void]$errors.Add("Story $($s.Ref) has no 'As a ..., I want ..., so that ...' line.") }
            elseif ($sdesc -match '(?m)^\s*<[^>]+>\s*$') { [void]$errors.Add("Story $($s.Ref) description still has a template placeholder.") }
            $ac = Join-Block $s.Ac
            if (-not $s.HasAc -or -not $ac) { [void]$errors.Add("Story $($s.Ref) has no '#### Acceptance criteria' section.") }
            elseif (($ac -notmatch '(?mi)^\s*Given\b') -or ($ac -notmatch '(?mi)^\s*When\b') -or ($ac -notmatch '(?mi)^\s*Then\b')) {
                [void]$errors.Add("Story $($s.Ref) acceptance criteria need Gherkin lines starting with Given, When, and Then.")
            }
            if ($ac -match '<context>|<action>|<result>') { [void]$errors.Add("Story $($s.Ref) acceptance criteria still have template placeholders.") }
        }
    }
    return $result
}

# ------------------------------------------------------------- markdown to HTML

function ConvertTo-Html {
    # Small, safe converter for ADO's HTML fields: paragraphs, lists, level-4 headings,
    # fenced code, `code`, and **bold**.
    param([string]$Text)
    if (-not $Text) { return "" }

    function Format-Inline([string]$s) {
        $s = [System.Net.WebUtility]::HtmlEncode($s)
        $s = [regex]::Replace($s, '`([^`]+)`', '<code>$1</code>')
        $s = [regex]::Replace($s, '\*\*([^*]+)\*\*', '<b>$1</b>')
        return $s
    }

    $out = New-Object System.Text.StringBuilder
    $para = New-Object System.Collections.ArrayList
    $inList = $false
    $inCode = $false

    $flushPara = {
        if ($para.Count -gt 0) {
            [void]$out.Append("<p>" + ((@($para) | ForEach-Object { Format-Inline $_ }) -join "<br>") + "</p>")
            $para.Clear()
        }
    }

    foreach ($line in ($Text -split "\r?\n")) {
        if ($line -match '^\s*```') {
            if ($inCode) { [void]$out.Append("</pre>"); $inCode = $false }
            else { & $flushPara; if ($inList) { [void]$out.Append("</ul>"); $inList = $false }; [void]$out.Append("<pre>"); $inCode = $true }
            continue
        }
        if ($inCode) { [void]$out.Append([System.Net.WebUtility]::HtmlEncode($line) + "`n"); continue }

        if ($line -match '^\s*$') { & $flushPara; if ($inList) { [void]$out.Append("</ul>"); $inList = $false }; continue }
        if ($line -match '^#{1,6}\s+(.+)$') {
            & $flushPara; if ($inList) { [void]$out.Append("</ul>"); $inList = $false }
            [void]$out.Append("<h4>" + (Format-Inline $Matches[1]) + "</h4>"); continue
        }
        if ($line -match '^\s*(?:[-*]|\d+\.)\s+(.+)$') {
            & $flushPara
            if (-not $inList) { [void]$out.Append("<ul>"); $inList = $true }
            [void]$out.Append("<li>" + (Format-Inline $Matches[1]) + "</li>"); continue
        }
        if ($inList) { [void]$out.Append("</ul>"); $inList = $false }
        [void]$para.Add($line.Trim())
    }
    & $flushPara
    if ($inList) { [void]$out.Append("</ul>") }
    if ($inCode) { [void]$out.Append("</pre>") }
    return $out.ToString()
}

# ------------------------------------------------------------- item list

function Get-Items {
    # Flattens the parsed file into Epic, Feature, and Story items in order.
    param($Parsed, [string]$ScopeName)
    $items = New-Object System.Collections.ArrayList
    $epicDesc = Join-Block $Parsed.EpicLines
    [void]$items.Add([ordered]@{ Ref = "Epic"; Kind = "Epic"; Level = 1; Title = $Parsed.EpicTitle; Parent = $null; ExistingId = $Parsed.EpicId; Description = $epicDesc; ReleaseNote = ""; Acceptance = ""; Markdown = $epicDesc })
    foreach ($f in $Parsed.Features) {
        $fref = "Feature $($f.Num)"
        $fdesc = Join-Block $f.Lines
        $rn = ((@($f.Release) | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join " ")
        [void]$items.Add([ordered]@{ Ref = $fref; Kind = "Feature"; Level = 2; Title = $f.Title; Parent = "Epic"; ExistingId = $null; Description = $fdesc; ReleaseNote = $rn; Acceptance = ""; Markdown = $fdesc })
        foreach ($s in $f.Stories) {
            # ADO gets only the story itself. Builder notes and the scope reference stay local.
            $story = Join-Block $s.Lines
            $work = Join-Block $s.Work
            $local = $story
            if ($work) { $local += "`n`n#### Notes for the builder`n`n$work" }
            $local += "`n`n#### Part of`n`n- Epic: $($Parsed.EpicTitle)`n- Feature $($f.Num): $($f.Title)`n- Scope: ``$ScopeName``, Story $($s.Ref)"
            [void]$items.Add([ordered]@{ Ref = "Story $($s.Ref)"; Kind = "Story"; Level = 3; Title = $s.Title; Parent = $fref; ExistingId = $null; Description = $story; ReleaseNote = ""; Acceptance = (Join-Block $s.Ac); Markdown = $local })
        }
    }
    return $items
}

# ------------------------------------------------------------- published.md

function Read-Published {
    param([string]$Path)
    $map = @{}
    $mode = $null
    if (-not (Test-Path $Path)) { return [pscustomobject]@{ Mode = $null; Ids = $map } }
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line -match '^-\s*Mode:\s*(\S+)') { $mode = $Matches[1] }
        $cells = @($line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        if ($line.TrimStart().StartsWith("|") -and $cells.Count -ge 4 -and $cells[0] -notmatch '^(Ref|:?-+:?)$' -and $cells[3]) {
            $map[$cells[0]] = $cells[3]
        }
    }
    return [pscustomobject]@{ Mode = $mode; Ids = $map }
}

function Initialize-Published {
    param([string]$Path, [string]$ScopeName, [string]$ModeLine)
    if (Test-Path $Path) { return }
    $md = @"
# Published: $ScopeName

- Mode: $ModeLine
- Created: $((Get-Date).ToString("yyyy-MM-dd"))

Work top to bottom. Start each story with ``/start <id> feature``.

| Ref | Type | Title | Id | Link |
|---|---|---|---|---|
"@
    Write-Utf8 $Path ($md + "`n")
}

function Add-PublishedRow {
    param([string]$Path, [string]$Ref, [string]$Type, [string]$Title, [string]$Id, [string]$Link)
    $t = $Title.Replace("|", "/")
    $row = "| $Ref | $Type | $t | $Id | $Link |`n"
    [System.IO.File]::AppendAllText($Path, $row, (New-Object System.Text.UTF8Encoding($false)))
}

# =================================================================== main

$folderPath = (Resolve-Path $Folder -ErrorAction SilentlyContinue)
if (-not $folderPath) { throw "Folder not found: $Folder" }
$folderPath = $folderPath.Path
$scopeName = Split-Path $folderPath -Leaf
$milestonesPath = Join-Path $folderPath "milestones.md"
if (-not (Test-Path $milestonesPath)) { throw "No milestones.md in $folderPath. Run /slice $scopeName first." }

$parsed = Read-Milestones $milestonesPath
$storyCount = 0
foreach ($f in $parsed.Features) { $storyCount += $f.Stories.Count }
$summary = "Epic: $($parsed.EpicTitle)$(if ($parsed.EpicId) { " (existing #$($parsed.EpicId))" }); $($parsed.Features.Count) feature(s), $storyCount story(ies); Status: $($parsed.Status)"

if ($parsed.Errors.Count -gt 0) {
    foreach ($e in $parsed.Errors) { Write-Output "FORMAT: $e" }
    if ($PSCmdlet.ParameterSetName -eq "Check") { exit 1 }
    throw "milestones.md has $($parsed.Errors.Count) format problem(s). Fix them (run with -Check to list them again)."
}

if ($PSCmdlet.ParameterSetName -eq "Check") {
    Write-Output "OK: $summary"
    exit 0
}

if ($parsed.Status -ne "APPROVED") {
    throw "milestones.md says 'Status: $($parsed.Status)'. Approve it first with /approve $scopeName milestones."
}

$items = Get-Items $parsed $scopeName
$typeName = @{ Epic = "Epic"; Feature = "Feature"; Story = $StoryType }

# Release notes go to their own ADO field, named in config.json (optional for -Csv and -Local).
$config = $null
if (Test-Path $ConfigPath) {
    try { $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json }
    catch { if (-not $Push) { Write-Output "NOTE: could not read $ConfigPath, so no release note field is known. $($_.Exception.Message)" } }
}
$hasReleaseNotes = @($items | Where-Object { $_.ReleaseNote }).Count -gt 0
function Write-ReleaseNoteSkipped([string]$Key) {
    if ($hasReleaseNotes) { Write-Output "NOTE: feature release notes were left out because ""$Key"" is not set in $ConfigPath. They are still in milestones.md." }
}

# ------------------------------------------------------------------ CSV
if ($Csv) {
    $rnColumn = [string](Get-Prop $config "releaseNoteColumn")
    $skipEpic = [bool]$parsed.EpicId
    $rows = foreach ($it in $items) {
        if ($it.Kind -eq "Epic" -and $skipEpic) { continue }
        $level = $(if ($skipEpic) { $it.Level - 1 } else { $it.Level })
        $row = [ordered]@{ "ID" = ""; "Work Item Type" = $typeName[$it.Kind] }
        $maxLevel = $(if ($skipEpic) { 2 } else { 3 })
        for ($i = 1; $i -le $maxLevel; $i++) { $row["Title $i"] = $(if ($i -eq $level) { $it.Title } else { "" }) }
        $row["Description"] = ConvertTo-Html $it.Description
        $row["Acceptance Criteria"] = ConvertTo-Html $it.Acceptance
        if ($rnColumn) { $row[$rnColumn] = $it.ReleaseNote }
        $row["Area Path"] = $AreaPath
        $row["Iteration Path"] = $IterationPath
        $row["Tags"] = $scopeName
        [pscustomobject]$row
    }
    $csvText = (@($rows) | ConvertTo-Csv -NoTypeInformation) -join "`r`n"
    $csvPath = Join-Path $folderPath "backlog.csv"
    Write-Utf8 $csvPath ($csvText + "`r`n")
    Write-Output "Wrote $(@($rows).Count) row(s): $summary"
    if ($skipEpic) { Write-Output "Epic #$($parsed.EpicId) already exists, so it is not in the file. Link the imported features to it in ADO." }
    if (-not $rnColumn) { Write-ReleaseNoteSkipped "releaseNoteColumn" }
    Write-Output $csvPath
    exit 0
}

$publishedPath = Join-Path $folderPath "published.md"
$published = Read-Published $publishedPath

# ------------------------------------------------------------------ Local
if ($Local) {
    if ($published.Mode -and $published.Mode -notlike "local*") { throw "published.md already records a '$($published.Mode)' export. Local items would duplicate it." }
    $newLocal = Join-Path $PSScriptRoot "..\work\New-LocalWorkItem.ps1"
    if (-not (Test-Path $newLocal)) { throw "New-LocalWorkItem.ps1 not found at $newLocal." }
    $workRoot = Split-Path $folderPath -Parent
    Initialize-Published $publishedPath $scopeName "local"
    $made = 0
    foreach ($it in $items) {
        if ($it.Kind -ne "Story") { continue }
        if ($published.Ids.ContainsKey($it.Ref)) { Write-Output "Skip $($it.Ref): already $($published.Ids[$it.Ref])"; continue }
        $out = @(& $newLocal -WorkRoot $workRoot -Title $it.Title -Type Feature -Description $it.Markdown -AcceptanceCriteria $it.Acceptance)
        $itemFolder = [string]$out[-1]
        $leaf = Split-Path $itemFolder -Leaf
        if ($leaf -notmatch '^(L\d+)-') { throw "Could not read the local id from '$itemFolder'." }
        $localId = $Matches[1]
        Add-PublishedRow $publishedPath $it.Ref "Local story" $it.Title $localId ".work/$leaf"
        Write-Output "Created $($it.Ref) as ${localId}: $($it.Title)"
        $made++
    }
    Write-Output "Created $made local work item(s): $summary"
    Write-Output $publishedPath
    exit 0
}

# ------------------------------------------------------------------ Push
if (-not (Test-Path $ConfigPath)) { throw "Config not found at $ConfigPath. Set up ADO (see config.example.json), or use -Csv." }
if (-not $config) { $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json }

$connections = [ordered]@{}
$connSource = Get-Prop $config "connections"
if ($connSource) { foreach ($p in $connSource.PSObject.Properties) { $connections[$p.Name] = $p.Value } }
elseif (Get-Prop $config "serverUrl") { $connections["default"] = $config }
if ($connections.Count -eq 0) { throw "config.json has no 'connections' (or 'serverUrl'). See config.example.json." }
$namesText = @($connections.Keys) -join ", "

$connName = $null
if ($From) {
    if (-not $connections.Contains($From)) { throw "UNKNOWN: '$From' is not a connection. Connections: $namesText" }
    $connName = $From
}
elseif (Get-Prop $config "default") { $connName = [string](Get-Prop $config "default") }
elseif ($connections.Count -eq 1) { $connName = @($connections.Keys)[0] }
else { throw "AMBIGUOUS: name the ADO connection with -From. Connections: $namesText" }
if (-not $connections.Contains($connName)) { throw "config.json 'default' is '$connName', which is not a connection. Connections: $namesText" }

$c = $connections[$connName]
$serverUrl = Get-Prop $c "serverUrl"
$collection = Get-Prop $c "collection"
if (-not $serverUrl -or -not $collection) { throw "Connection '$connName' needs 'serverUrl' and 'collection'." }
if ($serverUrl -match "example\.local") { throw "Connection '$connName' still has the example serverUrl. Fill in your real ADO Server URL in $ConfigPath." }
$apiVersion = $(if (Get-Prop $c "apiVersion") { Get-Prop $c "apiVersion" } elseif (Get-Prop $config "apiVersion") { Get-Prop $config "apiVersion" } else { "6.0" })
$auth = $(if (Get-Prop $c "auth") { Get-Prop $c "auth" } elseif (Get-Prop $config "auth") { Get-Prop $config "auth" } else { "pat" })
$patEnv = $(if (Get-Prop $c "patEnv") { Get-Prop $c "patEnv" } elseif (Get-Prop $config "patEnv") { Get-Prop $config "patEnv" } else { "ADO_PAT" })
if (-not $Project) { $Project = Get-Prop $c "project" }
$rnField = $(if (Get-Prop $c "releaseNoteField") { [string](Get-Prop $c "releaseNoteField") } else { [string](Get-Prop $config "releaseNoteField") })
if (-not $Project) { throw "No ADO project. Add 'project' to connection '$connName' in config.json, or pass -Project." }

$base = "$($serverUrl.TrimEnd('/'))/$collection"
$modeLine = "ado ($connName, $Project)"

if ($published.Mode -and $published.Mode -notlike "ado*") { throw "published.md already records a '$($published.Mode)' export. ADO items would duplicate it." }

if ($DryRun) {
    Write-Output "Connection : $connName ($base)"
    Write-Output "Project    : $Project"
    Write-Output "Area       : $(if ($AreaPath) { $AreaPath } else { '(project default)' })"
    Write-Output "Iteration  : $(if ($IterationPath) { $IterationPath } else { '(project default)' })"
    Write-Output "Release    : $(if ($rnField) { $rnField } else { '(releaseNoteField not set: release notes left out)' })"
    $n = 0
    foreach ($it in $items) {
        $indent = "  " * ($it.Level - 1)
        if ($it.ExistingId) { Write-Output "$indent$($it.Ref): existing #$($it.ExistingId)"; continue }
        if ($published.Ids.ContainsKey($it.Ref)) { Write-Output "$indent$($it.Ref): already created #$($published.Ids[$it.Ref])"; continue }
        Write-Output "$indent$($it.Ref) [$($typeName[$it.Kind])]: $($it.Title)"
        $n++
    }
    Write-Output "Would create $n item(s). $summary"
    exit 0
}

$headers = @{}
$useDefaultCreds = $false
if ($auth -eq "windows") { $useDefaultCreds = $true }
else {
    $pat = [Environment]::GetEnvironmentVariable($patEnv)
    if (-not $pat) { throw "$patEnv environment variable is not set (connection '$connName'). Set it, or use -Csv." }
    $headers.Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":" + $pat))
}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

Initialize-Published $publishedPath $scopeName $modeLine
$ids = @{}
foreach ($k in $published.Ids.Keys) { $ids[$k] = $published.Ids[$k] }
$made = 0

foreach ($it in $items) {
    if ($it.ExistingId) {
        $ids[$it.Ref] = [string]$it.ExistingId
        if (-not $published.Ids.ContainsKey($it.Ref)) { Add-PublishedRow $publishedPath $it.Ref "Epic" $it.Title ([string]$it.ExistingId) "$base/$([uri]::EscapeDataString($Project))/_workitems/edit/$($it.ExistingId)" }
        continue
    }
    if ($published.Ids.ContainsKey($it.Ref)) { Write-Output "Skip $($it.Ref): already #$($published.Ids[$it.Ref])"; continue }

    $ops = New-Object System.Collections.ArrayList
    [void]$ops.Add(@{ op = "add"; path = "/fields/System.Title"; value = $it.Title })
    if ($it.Description) { [void]$ops.Add(@{ op = "add"; path = "/fields/System.Description"; value = (ConvertTo-Html $it.Description) }) }
    if ($it.Acceptance) { [void]$ops.Add(@{ op = "add"; path = "/fields/Microsoft.VSTS.Common.AcceptanceCriteria"; value = (ConvertTo-Html $it.Acceptance) }) }
    if ($it.ReleaseNote -and $rnField) { [void]$ops.Add(@{ op = "add"; path = "/fields/$rnField"; value = $it.ReleaseNote }) }
    if ($AreaPath) { [void]$ops.Add(@{ op = "add"; path = "/fields/System.AreaPath"; value = $AreaPath }) }
    if ($IterationPath) { [void]$ops.Add(@{ op = "add"; path = "/fields/System.IterationPath"; value = $IterationPath }) }
    [void]$ops.Add(@{ op = "add"; path = "/fields/System.Tags"; value = $scopeName })
    if ($it.Parent) {
        $parentId = $ids[$it.Parent]
        if (-not $parentId) { throw "Parent $($it.Parent) of $($it.Ref) has no id. Nothing after this was created." }
        [void]$ops.Add(@{ op = "add"; path = "/relations/-"; value = @{ rel = "System.LinkTypes.Hierarchy-Reverse"; url = "$base/_apis/wit/workItems/$parentId" } })
    }

    $json = ConvertTo-Json -InputObject @($ops) -Depth 6
    $uri = "$base/$([uri]::EscapeDataString($Project))/_apis/wit/workitems/`$$([uri]::EscapeDataString($typeName[$it.Kind]))?api-version=$apiVersion"
    $req = @{ Method = "Post"; Uri = $uri; ContentType = "application/json-patch+json"; Body = ([Text.Encoding]::UTF8.GetBytes($json)) }
    if ($useDefaultCreds) { $req.UseDefaultCredentials = $true } else { $req.Headers = $headers }

    try { $created = Invoke-RestMethod @req }
    catch { throw "Creating $($it.Ref) '$($it.Title)' failed on '$connName' ($base, project $Project). $($_.Exception.Message) Items created before this are in published.md; run the same command again to continue." }

    $newId = [string]$created.id
    $link = Get-Prop (Get-Prop (Get-Prop $created "_links") "html") "href"
    if (-not $link) { $link = "$base/$([uri]::EscapeDataString($Project))/_workitems/edit/$newId" }
    $ids[$it.Ref] = $newId
    Add-PublishedRow $publishedPath $it.Ref $typeName[$it.Kind] $it.Title $newId $link
    Write-Output "Created $($it.Ref) as #${newId}: $($it.Title)"
    $made++
}

Write-Output "Created $made item(s) in ADO: $summary"
if (-not $rnField) { Write-ReleaseNoteSkipped "releaseNoteField" }
Write-Output $publishedPath
