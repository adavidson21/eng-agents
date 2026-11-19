<#
.SYNOPSIS
    Records which station a work item's build is at right now (Core 4.12.0), for Workshop's Loom floor.

.DESCRIPTION
    Writes <work folder>\step.md with one line:

      - Step: <build | test | ui | review | fix> | <ISO time>

    /do-task and /review call it as they move between building, running tests, UI checks, reviewing and fixing
    review findings, so Loom shows the item at the right station instead of guessing from the session's text.
    The file is replaced each time; it holds no history. Prints the step.

.EXAMPLE
    .\Set-Step.ps1 -Folder .work\L14-invite-members -Step test
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$Folder,
    [Parameter(Mandatory = $true)] [ValidateSet("build", "test", "ui", "review", "fix")] [string]$Step
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { throw "No work folder $Folder." }
$at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $Folder "step.md"), "- Step: $Step | $at`n", $enc)
Write-Output $Step
