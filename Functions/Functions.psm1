# ./Functions/Functions.psm1
# ------------------------------------------------------------
# PowerShell module that loads all function definitions
# for the Orphaned RBAC Cleanup automation.
# ------------------------------------------------------------

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

# Load all function .ps1 files
Get-ChildItem -Path $scriptPath -Filter *.ps1 -ErrorAction Stop | ForEach-Object {
    Write-Verbose "Loading function: $($_.Name)"
    . $_.FullName
}

# Optionally export functions explicitly
# (only export those you want visible outside the module)
$functionsToExport = @(
    'Add-LogEntry',
        'Connect-FederatedIdentity',
        'Initialize-PSModules',
        'Export-OrphanedAssignments',
        'Get-OrphanedAssignments',
        'Get-ManagementGroupHierarchy',
        'Test-FederatedIdentityConnection',
        'Show-Summary'
)

Export-ModuleMember -Function $functionsToExport
