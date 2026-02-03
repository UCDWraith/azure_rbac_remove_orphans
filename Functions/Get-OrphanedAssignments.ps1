<#
.SYNOPSIS
    Identifies orphaned Azure RBAC assignments for Management Groups, Subscriptions, or Resource Groups.

.DESCRIPTION
    For each RBAC role assignment under the specified scope, verifies whether the principal (user, group,
    or service principal) exists in Entra ID using Microsoft Graph. Supports optional recursion to scan
    all resource groups under a subscription when -IncludeResourceGroups is specified.

.PARAMETER ScopeType
    The type of Azure scope. Supported values:
    - ManagementGroup
    - Subscription
    - ResourceGroup

.PARAMETER ScopeId
    Identifier for the Azure scope. Examples:
        myMG
        11111111-2222-3333-4444-555555555555
        my-resource-group

.PARAMETER IncludeResourceGroups
    When used with -ScopeType Subscription, automatically enumerates and scans all resource groups
    within that subscription.

.PARAMETER LogFilePath
    Optional path to write diagnostic output.

.EXAMPLE
    Get-OrphanedAssignments -ScopeType Subscription -ScopeId "11111111-2222-3333-4444-555555555555" -IncludeResourceGroups

.EXAMPLE
    Get-OrphanedAssignments -ScopeType ResourceGroup -ScopeId "App-RG"

.NOTES
    Author: Paul Shortt
    Created: 2025-10-23
    Version: 4.0.0
    Required PowerShell Version: 7.2+
#>

function Get-OrphanedAssignments {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("ManagementGroup", "Subscription", "ResourceGroup")]
        [string]$ScopeType,

        [Parameter(Mandatory = $true)]
        [string]$ScopeId,

        [switch]$IncludeResourceGroups,

        [string]$LogFilePath
    )

    Add-LogEntry -Message "🔍 Starting orphaned RBAC assignment scan for $ScopeType '$ScopeId'..." -Level INFO -LogFilePath $LogFilePath
    $orphans = @()

    function Get-OrphanedForScope {
        param (
            [string]$ScopeType,
            [string]$TargetScope,
            [string]$TargetName
        )

        $localOrphans = @()
        $assignments = Get-AzRoleAssignment -Scope $TargetScope -ErrorAction SilentlyContinue
        if (-not $assignments) {
            Add-LogEntry -Message "ℹ️ No role assignments found for $ScopeType '$TargetName'." -Level INFO -LogFilePath $LogFilePath
            return @()
        }

        $count = 0
        foreach ($a in $assignments) {
            # Validate with Microsoft Graph
            $principalExists = Get-MgDirectoryObject -DirectoryObjectId $a.ObjectId -ErrorAction SilentlyContinue
            if (-not $principalExists) {
                $count++
                Add-LogEntry -Message "❌ Orphaned assignment: $($a.ObjectId) ($($a.RoleDefinitionName)) in $ScopeType '$TargetName'" -Level WARNING -LogFilePath $LogFilePath

                $record = [PSCustomObject]@{
                    RoleAssignmentName = $a.RoleAssignmentName
                    RoleAssignmentId   = $a.RoleAssignmentId
                    Scope              = $a.Scope
                    RoleDefinitionName = $a.RoleDefinitionName
                    RoleDefinitionId   = $a.RoleDefinitionId
                    ObjectId           = $a.ObjectId
                    ObjectType         = "Unknown"
                    TargetType         = $ScopeType
                    TargetName         = $TargetName
                }

                $localOrphans += $record
            }
        }

        if ($count -gt 0) {
            Add-LogEntry -Message "⚠️ Found $count orphaned assignments in $ScopeType '$TargetName'." -Level WARNING -LogFilePath $LogFilePath
        } else {
            Add-LogEntry -Message "✅ No orphaned assignments found in $ScopeType '$TargetName'." -Level SUCCESS -LogFilePath $LogFilePath
        }

        return $localOrphans
    }

    try {
        switch ($ScopeType) {

            # ----------------- Management Group -----------------
            "ManagementGroup" {
                $targetScope = "/providers/Microsoft.Management/managementGroups/$ScopeId"
                Add-LogEntry -Message "📦 Scanning Management Group: $ScopeId" -Level INFO -LogFilePath $LogFilePath
                $orphans += Get-OrphanedForScope -ScopeType "ManagementGroup" -TargetScope $targetScope -TargetName $ScopeId
            }

            # ----------------- Subscription -----------------
            "Subscription" {
                $targetScope = "/subscriptions/$ScopeId"
                $subscription = Get-AzSubscription -SubscriptionId $ScopeId -ErrorAction SilentlyContinue
                $scopeName = if ($subscription) { $subscription.Name } else { $ScopeId }
                Add-LogEntry -Message "📦 Scanning Subscription: $ScopeId ($scopeName)" -Level INFO -LogFilePath $LogFilePath

                $orphans += Get-OrphanedForScope -ScopeType "Subscription" -TargetScope $targetScope -TargetName $scopeName

                if ($IncludeResourceGroups) {
                    Add-LogEntry -Message "🔁 Recursively scanning all resource groups under subscription $scopeName..." -Level INFO -LogFilePath $LogFilePath
                    $resourceGroups = Get-AzResourceGroup -SubscriptionId $ScopeId -ErrorAction SilentlyContinue
                    foreach ($rg in $resourceGroups) {
                        $rgScope = "/subscriptions/$ScopeId/resourceGroups/$($rg.ResourceGroupName)"
                        $orphans += Get-OrphanedForScope -ScopeType "ResourceGroup" -TargetScope $rgScope -TargetName $rg.ResourceGroupName
                    }
                }
            }

            # ----------------- Resource Group -----------------
            "ResourceGroup" {
                if ($ScopeId -notmatch "/subscriptions/") {
                    $subscriptionId = (Get-AzContext).Subscription.Id
                    $targetScope = "/subscriptions/$subscriptionId/resourceGroups/$ScopeId"
                } else {
                    $targetScope = $ScopeId
                }

                $rgName = ($targetScope -split '/')[-1]
                Add-LogEntry -Message "📦 Scanning Resource Group: $rgName" -Level INFO -LogFilePath $LogFilePath
                $orphans += Get-OrphanedForScope -ScopeType "ResourceGroup" -TargetScope $targetScope -TargetName $rgName
            }
        }
    }
    catch {
        Add-LogEntry -Message "❌ Error processing $ScopeType '$ScopeId': $($_.Exception.Message)" -Level ERROR -LogFilePath $LogFilePath
    }

    Add-LogEntry -Message "🔚 Completed scan for $ScopeType '$ScopeId'. Total orphaned assignments: $($orphans.Count)" -Level INFO -LogFilePath $LogFilePath
    return $orphans
}