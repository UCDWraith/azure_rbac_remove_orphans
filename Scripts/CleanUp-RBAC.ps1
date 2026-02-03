<#
.SYNOPSIS
    Identifies and exports orphaned Azure RBAC assignments across subscriptions and management groups in parallel.

.DESCRIPTION
    Uses federated identity to connect to Azure and Microsoft Graph, then concurrently
    scans each subscription for orphaned RBAC assignments via Get-OrphanedAssignments.
    Management group scans are sequential. Results are merged and exported to JSON.

.NOTES
    Author: Paul Shortt
    Created: 2025-10-23
    Version: 2.0.0
    Requires PowerShell 7.2+
#>

param (
    [string]$OutputPath = "./UnknownAssignments.json",
    [string]$LogFilePath = "./Logs/Cleanup.log",
    [int]$MaxParallel = 6
)

#
# Configuration: Target Subscription Name Filter
$TargetSubscriptionName = "<Your Subscription Name>" # e.g., "Contoso Production"

# --------------------------------------------------------------------------------------------
# Import Functions Module
# --------------------------------------------------------------------------------------------
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath "../Functions/Functions.psm1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force -ErrorAction Stop
    Write-Host "🧩 Functions module imported successfully."
} else {
    Write-Error "❌ Functions module not found at $modulePath"
    exit 1
}

# --------------------------------------------------------------------------------------------
# Initialise & Authenticate
# --------------------------------------------------------------------------------------------
Add-LogEntry -Message "🔄 Loading modules..." -LogFilePath $LogFilePath
Initialize-PSModules
Connect-AzFederatedIdentity -LogFilePath $LogFilePath
Connect-AzFederatedIdentity -UseGraphToken $true -LogFilePath $LogFilePath

# --------------------------------------------------------------------------------------------
# Retrieve Subscriptions
# --------------------------------------------------------------------------------------------
Add-LogEntry -Message "📜 Retrieving enabled subscriptions..." -Level INFO -LogFilePath $LogFilePath

# Get all enabled subscriptions, filter by name
# Modify as needed for your environment - e.g., remove name filter to scan all subscriptions --> Where-Object {$_.State -eq "Enabled"}
$subscriptions = Get-AzSubscription | Where-Object {$_.State -eq "Enabled" -and $_.Name -eq $TargetSubscriptionName}

if (-not $subscriptions) {
    Add-LogEntry -Message "⚠️ No enabled subscriptions found." -Level WARNING -LogFilePath $LogFilePath
    exit 0
}

# --------------------------------------------------------------------------------------------
# Parallel Subscription Scan
# --------------------------------------------------------------------------------------------
Add-LogEntry -Message "⚙️ Starting parallel scan across subscriptions (max $MaxParallel threads)..." -Level INFO -LogFilePath $LogFilePath

# Define skip list and pattern
$skipList = @(
    "<SubscriptionID>" # placeholder or broken subscriptionID
)
$guidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

$subscriptionResults = @()

$subscriptionResults = $subscriptions | ForEach-Object -Parallel {
    param($guidPattern, $skipList, $using:LogFilePath)

    Import-Module "$using:PSScriptRoot/../Functions/Functions.psm1" -Force

    $id = $_.Id
    $name = $_.Name
    if ($id -notmatch $guidPattern -or $id -in $skipList) {
        Add-LogEntry -Message "⚠️ Skipping subscription $name ($id) — invalid or in skip list." -Level WARNING -LogFilePath $using:LogFilePath
        return
    }

    Add-LogEntry -Message "🚀 Scanning subscription: $name" -Level INFO -LogFilePath $using:LogFilePath
    $orphans = Get-OrphanedAssignments -ScopeType Subscription -ScopeId $id -LogFilePath $using:LogFilePath
    return $orphans

} -ThrottleLimit $MaxParallel

# Flatten parallel results and force array conversion
$subscriptionUnknowns = @($subscriptionResults | Where-Object { $_ } | ForEach-Object { $_ })

Add-LogEntry -Message "✅ Completed parallel subscription scans. Found $($subscriptionUnknowns.Count) orphaned assignments." -Level INFO -LogFilePath $LogFilePath

# --------------------------------------------------------------------------------------------
# Management Group Scan (Sequential)
# --------------------------------------------------------------------------------------------

<#
Issue with Management Group scans - currently commented out.

# Add-LogEntry -Message "📦 Scanning management groups..." -Level INFO -LogFilePath $LogFilePath
# $managementGroups = Get-AzManagementGroup -ErrorAction SilentlyContinue
# $managementGroupUnknowns = @()

# foreach ($mg in $managementGroups) {
#     Add-LogEntry -Message "🔍 Evaluating management group: $($mg.Name)" -Level INFO -LogFilePath $LogFilePath
#     $managementGroupUnknowns += Get-OrphanedAssignments -ScopeType ManagementGroup -ScopeId $mg.Name -LogFilePath $LogFilePath
# }

# Add-LogEntry -Message "✅ Management group scans complete. Found $($managementGroupUnknowns.Count) orphaned assignments." -Level INFO -LogFilePath $LogFilePath
#>
$managementGroupUnknowns = @()

# --------------------------------------------------------------------------------------------
# Combine & Export Results
# --------------------------------------------------------------------------------------------
$allUnknowns = @(
    @($subscriptionUnknowns)
    @($managementGroupUnknowns)
) | Where-Object { $_ -is [pscustomobject] -and $_.PSObject.Properties.Name -contains 'RoleAssignmentId' }

if ($allUnknowns.Count -gt 0) {
    Add-LogEntry -Message "💾 Exporting orphaned assignments to $OutputPath" -Level INFO -LogFilePath $LogFilePath
    Export-OrphanedAssignments -Assignments $allUnknowns -Path $OutputPath -LogFilePath $LogFilePath
    Add-LogEntry -Message "✅ Export complete. Total orphaned assignments: $($allUnknowns.Count)" -Level SUCCESS -LogFilePath $LogFilePath
} else {
    Add-LogEntry -Message "✅ No orphaned assignments detected across all scopes." -Level SUCCESS -LogFilePath $LogFilePath
}