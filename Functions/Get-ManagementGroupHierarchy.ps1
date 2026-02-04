<#
.SYNOPSIS
    Retrieves and flattens the full Azure Management Group hierarchy.

.DESCRIPTION
    Discovers the complete Azure Management Group (MG) hierarchy starting from a specified
    root management group and recursively traverses all child management groups.

    The function returns a flattened list of management groups with hierarchy metadata
    (level, parent, and path) to simplify downstream processing such as RBAC analysis,
    governance validation, and security hygiene automation.

    IMPORTANT:
    This function must run under an Azure context that includes a subscription where the
    'Microsoft.Management' resource provider is registered. Certain Az cmdlets and management
    group discovery flows may fail if the provider is not registered in the current
    subscription context.

.PARAMETER RootMg
    The name (ID) of the root management group to begin traversal from.
    If not specified, defaults to the tenant root management group name derived from
    the current Az context Tenant ID.

.PARAMETER LogFilePath
    Optional path to a log file for structured logging (if Add-LogEntry is available).

.OUTPUTS
    System.Management.Automation.PSCustomObject

    Each returned object represents a management group and includes:
      - Name        : Management group name (used for ARM scope resolution)
      - DisplayName : Friendly display name of the management group
      - Id          : Full Azure resource ID of the management group
      - ParentName  : Parent management group name (null for root)
      - Level       : Depth of the management group in the hierarchy
      - Path        : Hierarchical path from root to the management group

.EXAMPLE
    Get-ManagementGroupHierarchy

    Retrieves the full management group hierarchy starting from the tenant root.

.EXAMPLE
    Get-ManagementGroupHierarchy -RootMg "contoso-root"

    Retrieves the hierarchy starting from a specific management group.

.NOTES
    Author: Paul Shortt
    Version: 1.0.1
    Required PowerShell Version: 7.2+

    Prerequisites:
      - Reader (or higher) at the tenant root management group (or equivalent visibility)
      - The 'Microsoft.Management' resource provider must be registered in the current subscription context

.LINK
    https://learn.microsoft.com/azure/governance/management-groups/overview
#>

function Get-ManagementGroupHierarchy {
    [CmdletBinding()]
    param(
        [string]$RootMg = $null,
        [string]$LogFilePath
    )

    if (-not $RootMg) {
        $RootMg = (Get-AzContext).Tenant.Id
    }
    if (-not $RootMg) {
        throw "Unable to determine RootMg. Ensure Connect-AzAccount has run and Get-AzContext returns a tenant."
    }

    # -----------------------------------------------------------------------------------------
    # Pre-flight checks
    # -----------------------------------------------------------------------------------------

    # Confirm we have an Az context
    $ctx = Get-AzContext
    if (-not $ctx -or -not $ctx.Subscription -or -not $ctx.Subscription.Id) {
        $msg = "No Azure subscription context is available. Ensure Connect-AzAccount has run and a subscription is selected."
        if (Get-Command Add-LogEntry -ErrorAction SilentlyContinue) {
            Add-LogEntry -Message "❌ $msg" -Level ERROR -LogFilePath $LogFilePath
        }
        throw $msg
    }

    # Confirm Microsoft.Management RP is registered in the current subscription context
    try {
        $rp = Get-AzResourceProvider -ProviderNamespace "Microsoft.Management" -ErrorAction Stop
        if ($rp.RegistrationState -ne "Registered") {
            $msg = @"
                Microsoft.Management resource provider is not registered in subscription '$($ctx.Subscription.Id)'.
                Current state: '$($rp.RegistrationState)'.

                Remediation:
                az provider register --namespace Microsoft.Management
                (or)
                Register-AzResourceProvider -ProviderNamespace Microsoft.Management

                Re-run the function after the provider is registered.
"@.Trim()

            if (Get-Command Add-LogEntry -ErrorAction SilentlyContinue) {
                Add-LogEntry -Message "❌ $msg" -Level ERROR -LogFilePath $LogFilePath
            }
            throw $msg
        }
    }
    catch {
        $msg = "Unable to validate Microsoft.Management provider registration in subscription '$($ctx.Subscription.Id)'. $($_.Exception.Message)"
        if (Get-Command Add-LogEntry -ErrorAction SilentlyContinue) {
            Add-LogEntry -Message "❌ $msg" -Level ERROR -LogFilePath $LogFilePath
        }
        throw $msg
    }

    # Get full hierarchy as a tree
    $tree = Get-AzManagementGroup -GroupName $RootMg -Expand -Recurse -ErrorAction Stop

    # Flat results for consumption
    $results = New-Object System.Collections.Generic.List[object]

    # Track visited MG names to avoid loops/duplicates
    $visited = [System.Collections.Generic.HashSet[string]]::new()

    function Get-MgNameFromChild {
        param([Parameter(Mandatory)]$Child)

        # Child nodes often have Name; if not, derive from Id
        if ($Child.PSObject.Properties.Name -contains 'Name' -and $Child.Name) {
            return [string]$Child.Name
        }
        if ($Child.PSObject.Properties.Name -contains 'Id' -and $Child.Id) {
            return [string](($Child.Id -split '/')[-1])
        }
        return $null
    }

    function Test-ManagementGroupChild {
        param([Parameter(Mandatory)]$Child)

        # Be flexible: different Az versions return different type strings/casing
        $t = $null
        if ($Child.PSObject.Properties.Name -contains 'Type') { $t = [string]$Child.Type }
        if (-not $t) { return $false }

        return ($t -match 'managementGroups$') -or ($t -match 'Microsoft\.Management/managementGroups') -or ($t -match '/providers/Microsoft\.Management/managementGroups')
    }

    function Search-MgTree {
        param(
            [Parameter(Mandatory)]$Node,
            [string]$ParentName = $null,
            [int]$Level = 0,
            [string]$Path = $null
        )

        $nodeName = $Node.Name
        if (-not $nodeName) { return }

        if (-not $visited.Add([string]$nodeName)) {
            return
        }

        $nodePath = if ($Path) { "$Path/$nodeName" } else { "$nodeName" }

        $results.Add([pscustomobject]@{
            Name        = $Node.Name           # <-- consume this in Get-OrphanedAssignments -ScopeId
            DisplayName = $Node.DisplayName
            Id          = $Node.Id
            ParentName  = $ParentName
            Level       = $Level
            Path        = $nodePath
        })

        # If no children, stop
        $children = @()
        if ($Node.PSObject.Properties.Name -contains 'Children' -and $Node.Children) {
            $children = @($Node.Children)
        }

        # Helpful diagnostic: uncomment if needed
        # Write-Host ("DEBUG MG '{0}' children={1}" -f $nodeName, $children.Count)

        foreach ($child in $children) {
            if (-not (Test-ManagementGroupChild -Child $child)) {
                continue  # skip subscription children
            }

            $childName = Get-MgNameFromChild -Child $child
            if (-not $childName) { continue }

            # When -Recurse works properly, child may already contain nested Children.
            # If not, fetch the child explicitly to keep traversal reliable.
            $childNode = $child
            $hasNested = ($childNode.PSObject.Properties.Name -contains 'Children')

            if (-not $hasNested) {
                $childNode = Get-AzManagementGroup -GroupName $childName -Expand -ErrorAction Stop
            }

            Search-MgTree -Node $childNode -ParentName $nodeName -Level ($Level + 1) -Path $nodePath
        }
    }

    Search-MgTree -Node $tree -ParentName $null -Level 0 -Path $null

    # Return flat list ordered by depth/path
    return $results | Sort-Object Level, Path
}