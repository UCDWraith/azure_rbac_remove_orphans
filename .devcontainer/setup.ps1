# Ensure nuget provider is available
Install-PackageProvider -Name NuGet -Force -Scope AllUsers

# Trust PSGallery
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# Install the new PowerShellGet
Install-Module PowerShellGet -Force -AllowClobber -Scope AllUsers

# Load it
Import-Module PowerShellGet

# Install modules you need
Install-Module Az.Accounts -Force -Scope AllUsers
Install-Module Az.Resources -Force -Scope AllUsers
Install-Module Microsoft.Graph.DirectoryObjects -Force -Scope AllUsers
Install-Module Microsoft.Graph.Users -Force -Scope AllUsers