<#
.SYNOPSIS
    Writes a timestamped log message to the console, output stream, and optionally a log file.

.DESCRIPTION
    Formats log messages with a timestamp and log level for consistent output in both
    local and CI/CD environments. Messages can be displayed in colour on the console,
    emitted to the output stream, and optionally appended to a specified log file.

.PARAMETER Message
    The message text to log.

.PARAMETER Level
    The severity level for the message. Supported values:
    INFO (default), WARNING, ERROR, DEBUG, SUCCESS.

.PARAMETER NoConsole
    Suppresses console output and only writes to the PowerShell output stream
    (useful when redirecting or collecting logs programmatically).

.PARAMETER LogFilePath
    Optional path to a log file. When specified, messages are appended to the file
    in plain text format.

.EXAMPLE
    Add-LogEntry -Message "Starting scan of management groups"

.EXAMPLE
    Add-LogEntry -Message "RBAC assignments found" -Level SUCCESS -LogFilePath "C:\Logs\Cleanup.log"

.EXAMPLE
    Add-LogEntry -Message "User not found in directory" -Level WARNING -NoConsole

.EXAMPLE
    Add-LogEntry -Message "Quota nearly full" -Level WARNING -LogFilePath "$env:TEMP\cleanup.log"
    # Warning only to file

.EXAMPLE
    Add-LogEntry -Message "Debug trace enabled" -Level DEBUG -NoConsole
    # Debug output without console

.EXAMPLE
    Add-LogEntry -Message "Orphaned assignments exported" -Level SUCCESS -LogFilePath "$(Build.ArtifactStagingDirectory)/Logs/Cleanup.log"
    # Log to file in CI/CD environment

.NOTES
    Author: Paul Shortt
    Created: 2025-10-21
    Version: 1.1.1
    Required PowerShell Version: 7.2+
#>

function Add-LogEntry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'WARNING', 'ERROR', 'DEBUG', 'SUCCESS')]
        [string]$Level = 'INFO',

        [switch]$NoConsole,

        [string]$LogFilePath
    )

    # Format timestamp
    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $formattedMessage = "$timestamp [$Level] $Message"

    # Choose color for console output
    switch ($Level) {
        'INFO'     { $color = 'Gray' }
        'SUCCESS'  { $color = 'Green' }
        'WARNING'  { $color = 'Yellow' }
        'ERROR'    { $color = 'Red' }
        'DEBUG'    { $color = 'Cyan' }
        default    { $color = 'White' }
    }

    # Write to console unless suppressed
    if (-not $NoConsole) {
        Write-Host $formattedMessage -ForegroundColor $color
    } else {
        # If console is suppressed, emit to Information stream (still visible in CI if enabled)
        Write-Information $formattedMessage -InformationAction Continue
    }

    # Determine log file path in CI/CD if not specified
    if (-not $LogFilePath -and $env:BUILD_ARTIFACTSTAGINGDIRECTORY) {
        $LogFilePath = Join-Path $env:BUILD_ARTIFACTSTAGINGDIRECTORY "Logs/CleanupRBAC.log"
    }

    # Append to log file if path specified
    if ($LogFilePath) {
        try {
            # Ensure directory exists
            $logDir = Split-Path -Parent $LogFilePath
            if (-not (Test-Path $logDir)) {
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            }

            # Append message
            Add-Content -Path $LogFilePath -Value $formattedMessage
        } catch {
            Write-Warning "⚠️ Failed to write to log file '$LogFilePath': $($_.Exception.Message)"
        }
    }
}