<#
.SYNOPSIS
    Connects to Azure Resource Manager and/or Microsoft Graph using a federated identity via Azure CLI (OIDC/WIF).

.DESCRIPTION
    Connect-FederatedIdentity authenticates non-interactively in CI/CD (e.g., Azure DevOps) by retrieving access tokens
    from Azure CLI (which is already authenticated via a federated service connection / workload identity federation).

    Depending on -ConnectTo, the function will:
      - Connect to Azure Resource Manager using Connect-AzAccount (AccessToken-based), and/or
      - Connect to Microsoft Graph using Connect-MgGraph (AccessToken-based)

    The function prefers SecureString-based token usage and will fall back to plain token input if required,
    while preserving explicit, readable logging via Add-LogEntry.

.PARAMETER ConnectTo
    Specifies which endpoints to authenticate to.
      - Azure  : Connect to Azure Resource Manager (ARM) using Connect-AzAccount
      - Graph  : Connect to Microsoft Graph using Connect-MgGraph
      - Both   : Connect to both Azure and Graph (default)

.PARAMETER Resource
    The resource (audience) used when requesting an Azure access token from Azure CLI for ARM authentication.
    Default: https://management.azure.com/

    This parameter is only used when -ConnectTo includes Azure. For Graph authentication, the function uses:
    https://graph.microsoft.com/

    Examples of custom resources include:
      - https://vault.azure.net/ (Key Vault)
      - https://storage.azure.com/ (Storage)
    Note: For most Az.* cmdlets, the default ARM resource is appropriate.

.PARAMETER LogFilePath
    Optional path to a log file. When specified, log entries are appended to this file.
    The function assumes an Add-LogEntry helper is available and uses it for consistent output formatting.

.PARAMETER ExitOnFailure
    When specified, the function will terminate the PowerShell process with exit code 1 on failure.
    This is useful for CI/CD pipeline steps where you want the task to fail immediately.

    If not specified, the function will throw the underlying exception to allow upstream error handling.

.EXAMPLE
    # Connect to both Azure and Microsoft Graph (default)
    Connect-FederatedIdentity -LogFilePath $LogFilePath -ExitOnFailure

.EXAMPLE
    # Connect to Microsoft Graph only
    Connect-FederatedIdentity -ConnectTo Graph -LogFilePath $LogFilePath -ExitOnFailure

.EXAMPLE
    # Connect to Azure (ARM) only
    Connect-FederatedIdentity -ConnectTo Azure -LogFilePath $LogFilePath -ExitOnFailure

.EXAMPLE
    # Connect to Azure using a custom resource token (e.g., Key Vault)
    Connect-FederatedIdentity -ConnectTo Azure -Resource "https://vault.azure.net/" -LogFilePath $LogFilePath -ExitOnFailure

.NOTES
    Author: Paul Shortt
    Created: 2026-02-03
    Version: 1.0.0
    Required PowerShell Version: 7.2+

    Prerequisites:
      - Azure CLI must be available and already authenticated (e.g., via Azure DevOps service connection with WIF/OIDC)
      - Az.Accounts module for Azure connections
      - Microsoft.Graph.* modules for Graph connections
      - Add-LogEntry function available for logging (recommended)

    Typical usage:
      - Use in Azure DevOps AzureCLI@2 task (scriptType: pscore) where az is already logged in.
      - Use -ConnectTo Both for scripts that need both ARM (RBAC) and Graph (directory lookups).

#>

function Connect-FederatedIdentity {

    [CmdletBinding()]
    param (
        # What to connect to. Default: both Azure (ARM) and Graph.
        [ValidateSet('Azure', 'Graph', 'Both')]
        [string]$ConnectTo = 'Both',

        # ARM resource for Azure token retrieval (only used when ConnectTo includes Azure)
        [string]$Resource = "https://management.azure.com/",

        # Optional log file
        [string]$LogFilePath,

        # Keep your current behaviour by default (fail fast for pipelines),
        # but allow use in reusable modules/scripts without terminating the host.
        [switch]$ExitOnFailure
    )

    try {
        # -------------------------------
        # Connect to Microsoft Graph
        # -------------------------------
        if ($ConnectTo -in @('Graph','Both')) {

            $graphResource = "https://graph.microsoft.com/"
            Add-LogEntry -Message "🔐 Federated auth target: Microsoft Graph" -Level INFO -LogFilePath $LogFilePath
            Add-LogEntry -Message "Retrieving federated identity access token from Azure CLI (resource: $graphResource)..." -Level INFO -LogFilePath $LogFilePath

            $graphTokenResponse = az account get-access-token --resource $graphResource --output json | ConvertFrom-Json

            if (-not $graphTokenResponse.accessToken) {
                throw "Unable to retrieve Microsoft Graph access token. Ensure federated service connection + az context are valid."
            }

            $graphAccessTokenPlain = $graphTokenResponse.accessToken

            try {
                Add-LogEntry -Message "Connecting to Microsoft Graph using SecureString token..." -Level INFO -LogFilePath $LogFilePath
                $secureToken = ConvertTo-SecureString $graphAccessTokenPlain -AsPlainText -Force
                Connect-MgGraph -AccessToken $secureToken -ErrorAction Stop | Out-Null
                Add-LogEntry -Message "✅ Authenticated to Microsoft Graph (SecureString token)." -Level SUCCESS -LogFilePath $LogFilePath
            }
            catch {
                Add-LogEntry -Message "⚠️ SecureString Graph auth failed — retrying with plain token..." -Level WARNING -LogFilePath $LogFilePath
                Connect-MgGraph -AccessToken $graphAccessTokenPlain -ErrorAction Stop | Out-Null
                Add-LogEntry -Message "✅ Authenticated to Microsoft Graph (plain token)." -Level SUCCESS -LogFilePath $LogFilePath
            }
        }

        # -------------------------------
        # Connect to Azure (ARM)
        # -------------------------------
        if ($ConnectTo -in @('Azure','Both')) {

            Add-LogEntry -Message "🔐 Federated auth target: Azure Resource Manager" -Level INFO -LogFilePath $LogFilePath
            Add-LogEntry -Message "Retrieving federated identity access token from Azure CLI (resource: $Resource)..." -Level INFO -LogFilePath $LogFilePath

            $armTokenResponse = az account get-access-token --resource $Resource --output json | ConvertFrom-Json

            if (-not $armTokenResponse.accessToken) {
                throw "Unable to retrieve Azure (ARM) access token. Ensure federated service connection + az context are valid."
            }

            $armAccessTokenPlain = $armTokenResponse.accessToken
            $tenantId = $armTokenResponse.tenant

            $subscriptionId = (az account show --query id -o tsv)
            if (-not $subscriptionId) {
                throw "No subscription found in Azure CLI context. Ensure your federated service connection has subscription access."
            }

            $connectParams = @{
                AccessToken  = ConvertTo-SecureString $armAccessTokenPlain -AsPlainText -Force
                AccountId    = "federated-client"
                TenantId     = $tenantId
                Subscription = $subscriptionId
            }

            try {
                Add-LogEntry -Message "Connecting to Azure using SecureString token..." -Level INFO -LogFilePath $LogFilePath
                Connect-AzAccount @connectParams -ErrorAction Stop | Out-Null
                Add-LogEntry -Message "✅ Authenticated to Azure (SecureString token)." -Level SUCCESS -LogFilePath $LogFilePath
            }
            catch {
                Add-LogEntry -Message "⚠️ SecureString Azure auth failed — retrying with plain token..." -Level WARNING -LogFilePath $LogFilePath
                $connectParams.AccessToken = $armAccessTokenPlain
                Connect-AzAccount @connectParams -ErrorAction Stop | Out-Null
                Add-LogEntry -Message "✅ Authenticated to Azure (plain token)." -Level SUCCESS -LogFilePath $LogFilePath
            }

            # Avoid noisy subscription listings; just record context
            $context = Get-AzContext
            Add-LogEntry -Message "Connected Tenant: $($context.Tenant.Id)" -Level INFO -LogFilePath $LogFilePath
            Add-LogEntry -Message "Connected Subscription: $($context.Subscription.Id)" -Level INFO -LogFilePath $LogFilePath
        }

        Add-LogEntry -Message "✅ Federated authentication complete (ConnectTo=$ConnectTo)." -Level SUCCESS -LogFilePath $LogFilePath
    }
    catch {
        Add-LogEntry -Message "❌ Federated authentication failed: $($_.Exception.Message)" -Level ERROR -LogFilePath $LogFilePath
        if ($ExitOnFailure) { exit 1 }
        throw
    }
}