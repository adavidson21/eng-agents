<#
  Experiments for the improve loop (Bench's Improve tab). An experiment is a folder
  evals/experiments/<id>/ with:
    experiment.json   { version, id, kind (fix or trim), command, file (relative to core/), reason, case, created,
                        status (proposed, kept or dropped), results: [results file names] }
    overlay/<file>    the changed file, mirroring core/ (Invoke-Evals -Overlay runs it on a scratch install)
  evals/experiments/ is not committed (see .gitignore); keeping an experiment copies its file into core/.
#>

function Get-ExperimentsRoot { return (Join-Path $script:EvalsRoot "experiments") }

function New-ExperimentId([string]$Kind, [string]$Command) {
    $stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
    $rand = [guid]::NewGuid().ToString("N").Substring(0, 4)
    return "$Kind-$Command-$stamp-$rand"
}

function Save-Experiment {
    param([string]$Kind, [string]$Command, [string]$File, [string]$NewText, [string]$Reason, [string]$Case)
    if ($File -notmatch '^(commands|agents|guides|templates|stacks)/[A-Za-z0-9_.-]+\.md$' -and $File -ne "AGENTS.md") { throw "An experiment may change one prompt file under core/: $File" }
    $id = New-ExperimentId $Kind $Command
    $dir = Join-Path (Get-ExperimentsRoot) $id
    $dest = Join-Path (Join-Path $dir "overlay") $File
    New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
    [IO.File]::WriteAllText($dest, $NewText, $script:Utf8)
    $meta = [ordered]@{ version = 1; id = $id; kind = $Kind; command = $Command; file = $File; reason = $Reason; case = $(if ($Case) { $Case } else { $null }); created = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss"); status = "proposed"; results = @() }
    [IO.File]::WriteAllText((Join-Path $dir "experiment.json"), ($meta | ConvertTo-Json -Depth 4), $script:Utf8)
    return [pscustomobject]@{ Id = $id; Dir = $dir; Overlay = (Join-Path $dir "overlay") }
}

function Read-Experiment([string]$Id) {
    if ($Id -notmatch '^[a-z]+-[a-z0-9-]+$') { throw "Bad experiment id: $Id" }
    $p = Join-Path (Join-Path (Get-ExperimentsRoot) $Id) "experiment.json"
    if (-not (Test-Path -LiteralPath $p)) { throw "No experiment $Id" }
    return (Get-Content -Raw -LiteralPath $p | ConvertFrom-Json)
}

function Set-ExperimentStatus([string]$Id, [string]$Status, [string]$AddResult) {
    $p = Join-Path (Join-Path (Get-ExperimentsRoot) $Id) "experiment.json"
    $m = Get-Content -Raw -LiteralPath $p | ConvertFrom-Json
    if ($Status) { $m.status = $Status }
    if ($AddResult) { $m.results = @(@($m.results) + $AddResult | Where-Object { $_ } | Select-Object -Unique) }
    [IO.File]::WriteAllText($p, ($m | ConvertTo-Json -Depth 4), $script:Utf8)
}

# The "## " sections of a markdown file: Title (heading line), Start and End character offsets.
function Get-MdSections([string]$Text) {
    $ms = @([regex]::Matches($Text, '(?m)^## .+$'))
    $out = @()
    for ($i = 0; $i -lt $ms.Count; $i++) {
        $end = if ($i + 1 -lt $ms.Count) { $ms[$i + 1].Index } else { $Text.Length }
        $out += [pscustomobject]@{ Title = $ms[$i].Value.Substring(3).Trim(); Start = $ms[$i].Index; End = $end }
    }
    return $out
}
