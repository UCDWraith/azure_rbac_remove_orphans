<#
.SYNOPSIS
    Exports orphaned RBAC assignments to JSON.

.DESCRIPTION
    Takes a list of orphaned assignments and writes them to the specified path in JSON format.
    Optionally logs the operation to a specified log file.
#>

function Export-OrphanedAssignments {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [array]$Assignments,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string]$LogFilePath
    )

    try {
        if (-not $Assignments -or $Assignments.Count -eq 0) {
            Add-LogEntry -Message "ℹ️ No orphaned assignments to export." -Level INFO -LogFilePath $LogFilePath
            return
        }

        $json = $Assignments | ConvertTo-Json -Depth 10
        $directory = Split-Path -Parent $Path
        if (-not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }

        $json | Out-File -FilePath $Path -Encoding utf8
        Add-LogEntry -Message "💾 Exported $($Assignments.Count) orphaned assignments to $Path" -Level SUCCESS -LogFilePath $LogFilePath
    }
    catch {
        Add-LogEntry -Message "❌ Failed to export orphaned assignments: $($_.Exception.Message)" -Level ERROR -LogFilePath $LogFilePath
        throw
    }
}