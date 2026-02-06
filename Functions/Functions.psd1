# ./Functions/Functions.psd1
@{
    RootModule        = 'Functions.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '369ea4dc-6e1c-4bb3-8e01-43d6bd47516f'
    Author            = 'Paul Shortt'
    CompanyName       = 'YourOrganisationName'
    Description       = 'Reusable helper functions for Azure RBAC cleanup automation.'
    PowerShellVersion = '7.2'
    FunctionsToExport = @(
        'Add-LogEntry',
        'Connect-FederatedIdentity',
        'Initialize-PSModules',
        'Export-OrphanedAssignments',
        'Get-OrphanedAssignments',
        'Get-ManagementGroupHierarchy',
        'Test-FederatedIdentityConnection',
        'Show-Summary'
    )
    CmdletsToExport   = @()
    AliasesToExport   = @()
    PrivateData       = @{}
}
