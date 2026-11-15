<#
.SYNOPSIS
    Shared helper for Set-DraftHash.ps1 and Test-DraftHash.ps1. Dot-source it; it does nothing on its own.

.DESCRIPTION
    A gate file's draft hash is the SHA-256 of its text with the "Status:" and "Draft-hash:" lines left out,
    trailing spaces trimmed from each line and line endings made "\n". So changing only the Status line
    (what /approve does) or the line endings does not count as an edit; any other change does.
    The first 12 hex characters are kept.
#>

function Get-DraftHash {
    param([Parameter(Mandatory = $true)][string]$Text)
    $kept = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($Text -split "\r?\n")) {
        if ($line -match '^\s*(Status|Draft-hash)\s*:') { continue }
        $kept.Add($line.TrimEnd())
    }
    $norm = ($kept -join "`n").Trim()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($norm))
    }
    finally { $sha.Dispose() }
    $hex = -join ($bytes | ForEach-Object { $_.ToString("x2") })
    return $hex.Substring(0, 12)
}

# The value of the "Draft-hash:" line, or $null.
function Get-StoredDraftHash {
    param([string]$Text)
    $m = [regex]::Match($Text, '(?mi)^\s*Draft-hash\s*:\s*([0-9a-f]{12})\s*$')
    if ($m.Success) { return $m.Groups[1].Value.ToLowerInvariant() }
    return $null
}
