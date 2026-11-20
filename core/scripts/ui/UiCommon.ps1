# Shared by Test-Ui.ps1, Start-UiApp.ps1 and Stop-UiApp.ps1 (dot-source it): reading the repo guide's UI checks
# table and matching changed files against its UI files patterns.

function Get-UiTable([string]$Text) {
    $rows = @{}
    if (-not $Text) { return $rows }
    $in = $false
    foreach ($line in ($Text -split "\r?\n")) {
        if ($line -match '^\s*##\s+UI checks\s*$') { $in = $true; continue }
        if ($in -and $line -match '^\s*##\s') { break }
        if (-not $in) { continue }
        if ($line -match '^\s*\|\s*([^|]+?)\s*\|\s*(.*?)\s*\|\s*$') {
            $k = $Matches[1].Trim().ToLowerInvariant()
            $v = $Matches[2].Trim()
            if ($k -eq 'field' -or $k -match '^:?-+:?$') { continue }
            $v = ($v -replace '`', '').Trim()
            if ($v -match '^<.*>$' -or $v -match '^TODO') { $v = '' }
            $rows[$k] = $v
        }
    }
    return $rows
}

function Test-Glob([string]$File, [string[]]$Globs) {
    $f = $File -replace '\\', '/'
    foreach ($g in $Globs) {
        $g = ($g.Trim() -replace '\\', '/')
        if (-not $g) { continue }
        $rx = '^' + ([regex]::Escape($g) -replace '\\\*\\\*/', '(.*/)?' -replace '\\\*\\\*', '.*' -replace '\\\*', '[^/]*' -replace '\\\?', '.') + '$'
        if ($f -match $rx) { return $true }
        if ($g -notmatch '/' -and ((Split-Path $f -Leaf) -match $rx)) { return $true }
    }
    return $false
}

# The table's UI files patterns, as a list.
function Get-UiGlobs($Table) {
    if ($Table['ui files']) { return @($Table['ui files'] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
    return @()
}

# Files with uncommitted changes in a repo (what a task changed before its commit), relative paths.
function Get-UncommittedFiles([string]$Repo) {
    $lines = & git -C $Repo status --porcelain 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return @($lines | Where-Object { $_ } | ForEach-Object { ($_.Substring(3) -split ' -> ')[-1].Trim('"') })
}
