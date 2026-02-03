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

# Ensure required modules are loaded
Initialize-PSModules

# Authenticate to Azure
Connect-AzFederatedIdentity
Connect-AzFederatedIdentity -UseGraphToken $true

$targetfile = Join-Path $env:PIPELINE_WORKSPACE "RBACScanOutput/UnknownAssignments.json"
if (-not (Test-Path $targetfile)) {
    throw "Target file not found: $targetfile"
}

$newUnknowns = Get-Content -Raw $targetfile | ConvertFrom-Json
$newUnknowns = @($newUnknowns) | Where-Object { $_ -is [pscustomobject] -and $_.RoleAssignmentId }  # Ensure it's an array of objects with RoleAssignmentId

# Built-in Role Definition IDs (stable GUIDs)
$ownerRoleId = "b24988ac-6180-42a0-ab88-20f7382dd24c"  # Owner
$uaaRoleId   = "18d7d88d-d35e-4fb5-a5c3-7773c20a72d9"  # User Access Administrator

foreach ($unknown in $newUnknowns) {

    # Normalise values (defensive)
    $objectId  = ($unknown.ObjectId ?? "").ToString().Trim()
    $roleDefId = ($unknown.RoleDefinitionId ?? "").ToString().Trim()
    $scope     = ($unknown.Scope ?? "").ToString().Trim()
    $raId      = ($unknown.RoleAssignmentId ?? "").ToString().Trim()

    # --- Safeguard #1: verify principal exists in Entra (Graph) ---
    $principalExists = $false
    try {
        $null = Get-MgDirectoryObject -DirectoryObjectId $objectId -ErrorAction Stop
        $principalExists = $true
    } catch {
        $principalExists = $false
    }

    # --- Safeguard #2: verify role assignment still exists ---
    $assignment = $null
    try {
        $assignment = Get-AzRoleAssignment -RoleDefinitionId $roleDefId -ObjectId $objectId -Scope $scope -ErrorAction Stop
    } catch {
        # If this fails due to transient issues, treat as "doesn't exist" and skip
        Write-Output "DEBUG: Get-AzRoleAssignment failed for $raId :: $($_.Exception.Message)"
        $assignment = $null
    }

    $assignmentExists = $null -ne $assignment

    # Only proceed with removal if the principal is confirmed unknown AND assignment still exists
    if (-not $principalExists -and $assignmentExists) {

        # --- Guard clause: avoid deleting the last direct RBAC admin assignment at subscription scope ---
        $isAdminRole = $roleDefId -in @($ownerRoleId, $uaaRoleId)

        # Determine subscription scope from the scope or RoleAssignmentId
        # (RoleAssignmentId is most reliable if scope may be resource-level)
        $subId = $null
        if ($raId -match '^/subscriptions/([^/]+)/') { $subId = $Matches[1] }

        if ($isAdminRole -and $subId) {
            $subScope = "/subscriptions/$subId"

            # Guard only applies when the assignment is DIRECTLY at subscription scope (not RG/resource)
            if ($scope -ieq $subScope) {

                # Count direct Owner/UAA assignments at subscription scope (not inherited)
                $directAdmins = @()
                try {
                    $directAdmins = Get-AzRoleAssignment -Scope $subScope -ErrorAction Stop |
                        Where-Object {
                            $_.Scope -ieq $subScope -and $_.RoleDefinitionId -in @($ownerRoleId, $uaaRoleId)
                        }
                } catch {
                    Write-Output "DEBUG: Unable to enumerate direct subscription-scope admins for $subScope :: $($_.Exception.Message)"
                }

                if (@($directAdmins).Count -le 1) {
                    Write-Output "SKIP (platform safeguard): last direct RBAC admin assignment at $subScope. Not removing $raId"
                    continue
                }
            }
        }

        # --- Proceed with removal (your existing behaviour) ---
        Write-Output "Role Assignment to Unknown Principal, proceeding with removal: $raId"
        try {
            Remove-AzRoleAssignment -RoleDefinitionId $roleDefId -ObjectId $objectId -Scope $scope -ErrorAction Stop
            Write-Output "Successfully removed Role Assignment: $raId"
        } catch {
            # If Azure returns 412 PreconditionFailed, log and continue rather than hard-failing the whole run
            if ($_.Exception.Message -match 'PreconditionFailed|412') {
                Write-Output "SKIP (412 PreconditionFailed): $raId"
                Write-Output "SKIP (platform safeguard): last direct RBAC admin assignment at $subScope. Not removing $raId"
                continue
            }
            Write-Error "Failed to remove Role Assignment: $raId. Error: $($_.Exception.Message)"
        }

    } else {
        Write-Output "Skipping removal: $raId (principalExists=$principalExists assignmentExists=$assignmentExists)"
    }
}
