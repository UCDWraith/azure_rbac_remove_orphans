<#
.SYNOPSIS
    Writes a summary of results to console and pipeline logs.
.DESCRIPTION
    Displays key stats (groups scanned, orphaned count) 
    and outputs a structured JSON summary object.
.PARAMETER Assignments
    Array of orphaned assignments.
.PARAMETER ManagementGroups
    Array of scanned management groups.
.PARAMETER OutputPath
    Path of exported JSON file.
#>
function Show-Summary {
    param (
        [Parameter(Mandatory = $true)]
        [array]$Assignments,
        [Parameter(Mandatory = $true)]
        [array]$ManagementGroups,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    $summary = [PSCustomObject]@{
        TenantId                 = (Get-AzContext).Tenant.Id
        ManagementGroupsScanned  = $ManagementGroups.Count
        OrphanedAssignmentsFound = $Assignments.Count
        OutputFile               = (Resolve-Path $OutputPath).Path
        Timestamp                = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }

    Write-Host ""
    Write-Host "📊 ===== Summary ====="
    Write-Host "Management Groups Scanned: $($summary.ManagementGroupsScanned)"
    Write-Host "Orphaned Assignments Found: $($summary.OrphanedAssignmentsFound)"
    Write-Host "JSON Output: $($summary.OutputFile)"
    Write-Host "======================"
    Write-Host ""
    Write-Host ($summary | ConvertTo-Json -Depth 5)
}