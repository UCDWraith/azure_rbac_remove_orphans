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