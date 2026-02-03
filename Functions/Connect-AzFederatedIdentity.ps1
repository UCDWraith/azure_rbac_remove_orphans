<#
.SYNOPSIS
    Connects to Azure or Microsoft Graph using a federated identity via Azure CLI.

.DESCRIPTION
    Retrieves an access token from Azure CLI using a federated identity
    (OIDC-based service connection) and authenticates either to Azure Resource Manager
    or Microsoft Graph, depending on the selected resource target.

.PARAMETER Resource
    Custom resource URL for token retrieval (default: "https://management.azure.com/").
    Only used if -UseGraphToken is not specified.

.PARAMETER UseGraphToken
    When specified, uses the Microsoft Graph resource endpoint
    ("https://graph.microsoft.com/") and connects using Connect-MgGraph.

.EXAMPLE
    Connect-AzFederatedIdentity
.EXAMPLE
    Connect-AzFederatedIdentity -UseGraphToken
.EXAMPLE
    Connect-AzFederatedIdentity -Resource "https://vault.azure.net/"

.NOTES
    Author: Paul Shortt
    Created: 2025-10-21
    Version: 2.0.0
    Required PowerShell Version: 7.2+
#>

function Connect-AzFederatedIdentity {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Resource = "https://management.azure.com/",

        [switch]$UseGraphToken,

        [string]$LogFilePath
    )

    try {
        if ($UseGraphToken) {
            $Resource = "https://graph.microsoft.com/"
            Add-LogEntry -Message "Using Microsoft Graph resource for federated authentication." -Level INFO -LogFilePath $LogFilePath
        } else {
            Add-LogEntry -Message "Using Azure Resource Manager resource for federated authentication." -Level INFO -LogFilePath $LogFilePath
        }

        # Retrieve access token from Azure CLI
        Add-LogEntry -Message "Retrieving federated identity access token from Azure CLI..." -Level INFO -LogFilePath $LogFilePath
        $tokenResponse = az account get-access-token --resource $Resource --output json | ConvertFrom-Json

        if (-not $tokenResponse.accessToken) {
            throw "Unable to retrieve access token. Ensure your federated service connection is configured correctly."
        }

        $accessTokenPlain = $tokenResponse.accessToken
        $tenantId = $tokenResponse.tenant

        # ----------------------------------------------------------
        # If connecting to Microsoft Graph
        # ----------------------------------------------------------
        if ($UseGraphToken) {
            try {
                # Prefer SecureString authentication first
                Add-LogEntry -Message "Connecting to Microsoft Graph using SecureString token..." -Level INFO -LogFilePath $LogFilePath
                $secureToken = ConvertTo-SecureString $accessTokenPlain -AsPlainText -Force
                Connect-MgGraph -AccessToken $secureToken -ErrorAction Stop
                Add-LogEntry -Message "✅ Authenticated to Microsoft Graph using SecureString access token." -Level SUCCESS -LogFilePath $LogFilePath
            }
            catch {
                Write-Warning "⚠️ SecureString connection to Microsoft Graph failed, retrying with plain token..."
                Connect-MgGraph -AccessToken $accessTokenPlain
                Add-LogEntry -Message "✅ Authenticated to Microsoft Graph using plain access token." -Level SUCCESS -LogFilePath $LogFilePath
            }

            return
        }

        # ----------------------------------------------------------
        # If connecting to Azure (ARM)
        # ----------------------------------------------------------
        $subscriptionId = (az account show --query id -o tsv)
        if (-not $subscriptionId) {
            throw "No subscription found in Azure CLI context. Ensure your federated service connection has subscription access."
        }

        $connectParams = @{
            AccessToken  = ConvertTo-SecureString $accessTokenPlain -AsPlainText -Force
            AccountId    = "federated-client"
            TenantId     = $tenantId
            Subscription = $subscriptionId
        }

        try {
            Add-LogEntry -Message "Connecting to Azure using SecureString token..." -Level INFO -LogFilePath $LogFilePath
            Connect-AzAccount @connectParams -ErrorAction Stop | Out-Null
            Add-LogEntry -Message "✅ Authenticated to Azure using federated identity SecureString token." -Level SUCCESS -LogFilePath $LogFilePath
        }
        catch {
            Write-Warning "⚠️ SecureString connection to Azure failed, retrying with plain token..."
            $connectParams.AccessToken = $accessTokenPlain
            Connect-AzAccount @connectParams -ErrorAction Stop | Out-Null
            Add-LogEntry -Message "✅ Authenticated to Azure using plain string token." -Level SUCCESS -LogFilePath $LogFilePath
        }

        $context = Get-AzContext
        Add-LogEntry -Message "Connected Tenant: $($context.Tenant.Id)" -Level INFO -LogFilePath $LogFilePath
        Add-LogEntry -Message "Connected Subscription: $($context.Subscription.Id)" -Level INFO -LogFilePath $LogFilePath
    }
    catch {
        Write-Warning "❌ Authentication via federated identity failed: $($_.Exception.Message)"
        exit 1
    }
}