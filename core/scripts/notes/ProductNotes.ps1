# Shared helpers for product notes: one note per product in Workshop's Notes app, in
# <Workshop data folder>/notes/products/<slug>.md. Dot-source this file; it defines functions only.
#
# The rules Tandem follows when it writes these notes are Notes' contract (adavidson21/notes README,
# "Tandem and product notes"): write only products/ and history/, keep a snapshot of the text it replaces in
# Notes' history format, write atomically, set tandem-changed, never touch reviewed.
#
# Works in Windows PowerShell 5.1 and PowerShell 7.

Set-StrictMode -Version 2.0

$script:NotesKeep = 20
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)

$script:BuiltInTemplate = @"
---
title: {{title}}
also-called: []
repos: []
tags: [product, product/{{slug}}]
---
# {{title}}

## Summary

## Business rules

## Gotchas

## People

## Decisions

## Links

## Remembered
"@

function Get-WorkshopHome {
    if ($env:WORKSHOP_HOME) { return $env:WORKSHOP_HOME }
    return (Join-Path $HOME ".workshop")
}

# Where product notes live, or why they are not available.
# Returns @{ Ok; Reason; DataDir; NotesDir; ProductsDir }.
function Get-ProductNotesHome {
    $wsHome = Get-WorkshopHome
    $config = Join-Path $wsHome "config.json"
    if (-not (Test-Path -LiteralPath $config -PathType Leaf)) {
        return @{ Ok = $false; Reason = "Workshop is not installed on this computer (no $config)." }
    }
    try { $cfg = Get-Content -LiteralPath $config -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { return @{ Ok = $false; Reason = "Could not read $config." } }
    $dataDir = $null
    if ($cfg.PSObject.Properties.Name -contains "dataDir" -and $cfg.dataDir) { $dataDir = [string]$cfg.dataDir }
    if (-not $dataDir) { $dataDir = Join-Path $HOME "Workshop" }
    if ($dataDir.StartsWith("~")) { $dataDir = Join-Path $HOME $dataDir.Substring(1).TrimStart("/", "\") }

    $apps = Join-Path $wsHome "apps.json"
    if (Test-Path -LiteralPath $apps -PathType Leaf) {
        try {
            $sw = Get-Content -LiteralPath $apps -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($sw.PSObject.Properties.Name -contains "off" -and (@($sw.off) -contains "notes")) {
                return @{ Ok = $false; Reason = "Notes is switched off in Workshop (Settings, Apps)." }
            }
        } catch { }
    }
    if (-not (Test-Path -LiteralPath $dataDir -PathType Container)) {
        return @{ Ok = $false; Reason = "The Workshop data folder $dataDir does not exist." }
    }
    $notesDir = Join-Path $dataDir "notes"
    return @{ Ok = $true; Reason = ""; DataDir = $dataDir; NotesDir = $notesDir; ProductsDir = (Join-Path $notesDir "products") }
}

# A product name as a Workshop file name: lowercase letters, digits and -, at most 40 characters.
function ConvertTo-NoteSlug([string]$Name) {
    $s = ($Name.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ($s.Length -gt 40) { $s = $s.Substring(0, 40).TrimEnd('-') }
    if (-not $s) { $s = "untitled" }
    return $s
}

# 32-bit FNV-1a of the UTF-16 code units, unsigned, in base 36 (Notes js/history.js hash).
function Get-NotesHash([string]$Text) {
    [uint64]$h = 2166136261
    foreach ($ch in $Text.ToCharArray()) {
        $h = $h -bxor [uint64][int]$ch
        $h = ($h * 16777619) % 4294967296
    }
    $digits = "0123456789abcdefghijklmnopqrstuvwxyz"
    if ($h -eq 0) { return "0" }
    $out = ""
    while ($h -gt 0) { $out = "$($digits[[int]($h % 36)])$out"; $h = [uint64](($h - ($h % 36)) / 36) }
    return $out
}

# The one-segment history folder name for a note path (Notes js/history.js historyKey).
function Get-NotesHistoryKey([string]$Path) {
    $flat = (($Path -replace '\.md$', '') -replace '[^a-z0-9]+', '-').Trim('-')
    if (-not $flat) { $flat = "note" }
    $h = Get-NotesHash $Path
    $max = 39 - $h.Length
    if ($flat.Length -gt $max) { $flat = $flat.Substring(0, $max) }
    return "$($flat.TrimEnd('-'))-$h"
}

# A snapshot file name for a UTC time: 20261105t171230123z.md.
function Get-NotesStamp([datetime]$Utc) {
    return $Utc.ToString("yyyyMMdd't'HHmmssfff'z.md'", [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-IsoNow([datetime]$Utc) {
    return $Utc.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
}

function Read-NoteText([string]$File) {
    return [System.IO.File]::ReadAllText($File, $script:Utf8)
}

# Write a file atomically: a temp file next to it, then replace. Retries briefly (OneDrive can hold files).
function Write-NoteAtomic([string]$File, [string]$Text) {
    $dir = Split-Path -Parent $File
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $tmp = Join-Path $dir (".tandem-" + [guid]::NewGuid().ToString("N") + ".tmp")
    [System.IO.File]::WriteAllText($tmp, $Text, $script:Utf8)
    for ($try = 1; ; $try++) {
        try {
            if (Test-Path -LiteralPath $File) { [System.IO.File]::Replace($tmp, $File, $null) }
            else { [System.IO.File]::Move($tmp, $File) }
            return
        } catch [System.IO.IOException] {
            if ($try -ge 5) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; throw }
            Start-Sleep -Milliseconds 200
        }
    }
}

# Keep the note's current text in history/ (always), then trim to the newest 20; older ones go to the trash.
function Save-NoteSnapshot([hashtable]$Where, [string]$RelPath, [string]$Text, [datetime]$Utc) {
    if (-not $Text.Trim()) { return $null }
    $key = Get-NotesHistoryKey $RelPath
    $dir = Join-Path (Join-Path $Where.NotesDir "history") $key
    $file = Join-Path $dir (Get-NotesStamp $Utc)
    Write-NoteAtomic $file $Text
    $snaps = @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -match '^\d{8}t\d{9}z\.md$' } | Sort-Object Name -Descending)
    if ($snaps.Count -gt $script:NotesKeep) {
        $trash = Join-Path (Join-Path (Join-Path (Join-Path $Where.DataDir ".trash") "notes") "history") $key
        New-Item -ItemType Directory -Path $trash -Force | Out-Null
        foreach ($old in $snaps[$script:NotesKeep..($snaps.Count - 1)]) {
            Move-Item -LiteralPath $old.FullName -Destination (Join-Path $trash $old.Name) -Force
        }
    }
    return "history/$key/$(Get-NotesStamp $Utc)"
}

# Split a note into lines, its newline, and the number of frontmatter lines.
function Split-Note([string]$Text) {
    $nl = "`n"
    if ($Text.Contains("`r`n")) { $nl = "`r`n" }
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($l in ($Text -split "\r?\n")) { $lines.Add($l) }
    $fm = 0
    if ($lines.Count -gt 0 -and $lines[0].TrimStart([char]0xFEFF) -match '^---\s*$') {
        for ($i = 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^---\s*$') { $fm = $i + 1; break } }
    }
    return @{ Lines = $lines; Nl = $nl; Front = $fm }
}

function Join-Note([hashtable]$Note) { return ($Note.Lines -join $Note.Nl) }

# Set a frontmatter field (added when missing, frontmatter made when there is none).
function Set-NoteField([hashtable]$Note, [string]$Key, [string]$Value) {
    $line = "${Key}: $Value"
    if ($Note.Front -eq 0) {
        $Note.Lines.Insert(0, "---"); $Note.Lines.Insert(1, $line); $Note.Lines.Insert(2, "---")
        $Note.Front = 3
        return
    }
    for ($i = 1; $i -lt $Note.Front - 1; $i++) {
        if ($Note.Lines[$i] -match ('^' + [regex]::Escape($Key) + '\s*:')) { $Note.Lines[$i] = $line; return }
    }
    $Note.Lines.Insert($Note.Front - 1, $line)
    $Note.Front++
}
