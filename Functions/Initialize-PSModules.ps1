<#
.SYNOPSIS
    Ensures all required PowerShell modules for Azure and Microsoft Graph are installed.

.DESCRIPTION
    Verifies that the necessary Az and Microsoft Graph modules are available in the current
    PowerShell session. If any modules are missing (or if -ForceReinstall is specified),
    the function installs or reinstalls them for the current user scope.
    This is especially useful for Azure DevOps pipeline agents or clean environments.

.PARAMETER ForceReinstall
    Forces reinstallation of all required modules, even if they are already installed.

.EXAMPLE
    Initialize-PSModules

.EXAMPLE
    Initialize-PSModules -ForceReinstall

    Initialize-PSModules -Modules @(
        "Az.Accounts",
        "Az.Resources",
        "Microsoft.Graph.Authentication",
        "Microsoft.Graph.Applications"
    )

    Initialize-PSModules `
        -Modules @("Az.Accounts","Az.Resources") `
        -ForceReinstall

    Ensure minimum versions are installed:
    Initialize-PSModules -Modules @(
        @{ Name="Az.Accounts"; MinimumVersion="2.13.0" },
        @{ Name="Az.Resources"; MinimumVersion="6.0.0" },
        @{ Name="Microsoft.Graph.Authentication"; MinimumVersion="2.28.0" }
    )

    Ensure specific versions are installed:
    Initialize-PSModules -Modules @(
        @{ Name="Microsoft.Graph.Authentication"; RequiredVersion="2.28.0" },
        @{ Name="Az.Accounts"; RequiredVersion="2.13.1" }
    )

    In this example, the Microsoft.Graph.Beta.Users module is marked as optional.
    If its installation fails, the function will continue without throwing an error.
    Initialize-PSModules -Modules @(
        @{ Name="Az.Accounts"; MinimumVersion="2.13.0" },
        @{ Name="Microsoft.Graph.Beta.Users"; MinimumVersion="2.0.0"; Optional=$true }
    )
    In this example, the Microsoft.Graph.Beta.Users module is marked as optional.
    If its installation fails, the function will continue without throwing an error.

.NOTES
    Author: Paul Shortt
    Created: 2025-10-21
    Version: 1.2.0
    Required PowerShell Version: 7.2+
#>

function Initialize-PSModules {
    [CmdletBinding()]
    param (
        # Backwards compatible:
        # - string[]: @("Az.Accounts","Az.Resources")
        # - object[]: @(
        #     @{ Name="Az.Accounts"; MinimumVersion="2.13.0" },
        #     @{ Name="Microsoft.Graph.Authentication"; RequiredVersion="2.28.0"; AllowPrerelease=$false }
        #   )
        [Parameter()]
        [object[]]$Modules = @(
            @{ Name="Az.Accounts";  MinimumVersion="2.0.0" },
            @{ Name="Az.Resources"; MinimumVersion="2.0.0" },
            @{ Name="Microsoft.Graph.DirectoryObjects"; MinimumVersion="2.0.0" },
            @{ Name="Microsoft.Graph.Users"; MinimumVersion="2.0.0" }
        ),

        [switch]$ForceReinstall
    )

    Write-Host "🔍 Checking required PowerShell modules..."

    # Normalise module specs to a common shape
    $moduleSpecs = foreach ($m in $Modules) {
        if ($m -is [string]) {
            [pscustomobject]@{
                Name            = $m
                MinimumVersion  = $null
                RequiredVersion = $null
                AllowPrerelease = $false
                Optional        = $false
            }
        }
        elseif ($m -is [hashtable] -or $m -is [pscustomobject]) {
            $name = $m.Name
            if (-not $name) { throw "Module spec is missing required property 'Name'." }

            [pscustomobject]@{
                Name            = [string]$name
                MinimumVersion  = if ($m.MinimumVersion)  { [version]$m.MinimumVersion } else { $null }
                RequiredVersion = if ($m.RequiredVersion) { [version]$m.RequiredVersion } else { $null }
                AllowPrerelease = [bool]($m.AllowPrerelease)
                Optional        = [bool]($m.Optional)
            }
        }
        else {
            throw "Unsupported module spec type '$($m.GetType().FullName)'. Use string or hashtable/pscustomobject."
        }
    }

    foreach ($spec in $moduleSpecs) {
        $name = $spec.Name

        try {
            # Get all installed versions (if any), highest first
            $installed = Get-Module -ListAvailable -Name $name |
                Sort-Object Version -Descending

            $installedTop = $installed | Select-Object -First 1
            $installedVer = if ($installedTop) { [version]$installedTop.Version } else { $null }

            # Determine if the installed version satisfies requirements
            $meetsRequirement = $false
            if ($ForceReinstall) {
                $meetsRequirement = $false
            }
            elseif (-not $installedTop) {
                $meetsRequirement = $false
            }
            elseif ($spec.RequiredVersion) {
                $meetsRequirement = ($installedVer -eq $spec.RequiredVersion)
            }
            elseif ($spec.MinimumVersion) {
                $meetsRequirement = ($installedVer -ge $spec.MinimumVersion)
            }
            else {
                $meetsRequirement = $true
            }

            if ($meetsRequirement) {
                if ($spec.RequiredVersion) {
                    Write-Host "✅ Module available: $name (installed $installedVer, required $($spec.RequiredVersion))"
                }
                elseif ($spec.MinimumVersion) {
                    Write-Host "✅ Module available: $name (installed $installedVer, minimum $($spec.MinimumVersion))"
                }
                else {
                    Write-Host "✅ Module available: $name (installed $installedVer)"
                }
                continue
            }

            # Install / reinstall
            if ($ForceReinstall) {
                Write-Host "♻️ Force reinstalling module: $name"
            }
            else {
                Write-Host "📦 Installing/upgrading module: $name"
            }

            $installParams = @{
                Name         = $name
                Force        = $true
                Scope        = "CurrentUser"
                AllowClobber = $true
                ErrorAction  = "Stop"
            }

            if ($spec.RequiredVersion) {
                $installParams.RequiredVersion = $spec.RequiredVersion.ToString()
            }
            elseif ($spec.MinimumVersion) {
                # Install-Module supports -MinimumVersion. It won't necessarily pick "latest" unless needed.
                $installParams.MinimumVersion = $spec.MinimumVersion.ToString()
            }

            if ($spec.AllowPrerelease) {
                $installParams.AllowPrerelease = $true
            }

            Install-Module @installParams

            # Re-check version after install
            $post = Get-Module -ListAvailable -Name $name | Sort-Object Version -Descending | Select-Object -First 1
            $postVer = if ($post) { [version]$post.Version } else { $null }

            if (-not $post) {
                throw "Module '$name' did not appear in module path after installation."
            }

            # Validate requirement after install
            $postOk = $true
            if ($spec.RequiredVersion) { $postOk = ($postVer -eq $spec.RequiredVersion) }
            elseif ($spec.MinimumVersion) { $postOk = ($postVer -ge $spec.MinimumVersion) }

            if ($postOk) {
                Write-Host "✅ Installed: $name ($postVer)"
            }
            else {
                throw "Installed version '$postVer' does not meet requirement for '$name'."
            }
        }
        catch {
            if ($spec.Optional) {
                Write-Warning "⚠️ Optional module failed: '$name' :: $($_.Exception.Message)"
                continue
            }
            Write-Warning "⚠️ Failed to install or verify module '$name': $($_.Exception.Message)"
        }
    }

    Write-Host ""
    if ($ForceReinstall) {
        Write-Host "✅ Module verification complete (force reinstall mode)."
    } else {
        Write-Host "✅ Module verification complete."
    }
}