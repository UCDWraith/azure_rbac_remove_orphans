<#
.SYNOPSIS
    Validates and monitors the current federated identity connection to Azure and/or Microsoft Graph.

.DESCRIPTION
    Checks whether Azure and Microsoft Graph sessions are active, determines token expiry time and
    remaining lifetime, and optionally re-authenticates using federated credentials if expired or missing.

.PARAMETER ReconnectIfNeeded
    Automatically re-authenticates using Connect-AzFederatedIdentity if the current
    session is invalid or expired.

.PARAMETER TestGraph
    Tests Microsoft Graph connectivity in addition to Azure.

.PARAMETER LogFilePath
    Optional path to write detailed results to a log file.

.EXAMPLE
    Test-FederatedIdentityConnection -TestGraph -ReconnectIfNeeded -LogFilePath "./Logs/Auth.log"

.NOTES
    Author: Paul Shortt
    Created: 2025-10-22
    Version: 2.1.0
    Required PowerShell Version: 7.2+
#>

function Test-FederatedIdentityConnection {

    [CmdletBinding()]
    param (
        [switch]$ReconnectIfNeeded,
        [switch]$TestGraph,
        [string]$LogFilePath
    )

    $isAzureConnected = $false
    $isGraphConnected = $false
    $azureTokenInfo = $null
    $graphTokenInfo = $null

    Add-LogEntry -Message "🔍 Validating federated identity connection status..." -Level INFO -LogFilePath $LogFilePath

    function Decode-JwtPayload {
        param([string]$Jwt)
        try {
            $segments = $Jwt.Split('.')
            if ($segments.Count -lt 2) { return $null }
            $payload = $segments[1].Replace('-', '+').Replace('_', '/')
            switch ($payload.Length % 4) {
                2 { $payload += '==' }
                3 { $payload += '=' }
            }
            $json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($payload))
            return ($json | ConvertFrom-Json)
        } catch {
            Add-LogEntry -Message "⚠️ Failed to decode JWT: $($_.Exception.Message)" -Level WARNING -LogFilePath $LogFilePath
            return $null
        }
    }

    # --- Validate Azure connection ---
    try {
        $context = Get-AzContext -ErrorAction SilentlyContinue
        if ($context -and $context.Account -and $context.Subscription) {
            Add-LogEntry -Message "✅ Azure context found: $($context.Account.Id) / $($context.Subscription.Id)" -Level SUCCESS -LogFilePath $LogFilePath
            $isAzureConnected = $true

            # Retrieve and decode Azure token
            $tokenResponse = az account get-access-token --resource https://management.azure.com/ --output json | ConvertFrom-Json
            if ($tokenResponse.accessToken) {
                $azureTokenInfo = Decode-JwtPayload -Jwt $tokenResponse.accessToken
                if ($azureTokenInfo.exp) {
                    $expiry = [DateTimeOffset]::FromUnixTimeSeconds([int64]$azureTokenInfo.exp).ToLocalTime()
                    $remaining = ($expiry - (Get-Date)).TotalMinutes
                    Add-LogEntry -Message "🔑 Azure token expires at: $($expiry) ($([math]::Round($remaining,1)) minutes remaining)" -Level INFO -LogFilePath $LogFilePath
                    if ($remaining -le 10 -and $ReconnectIfNeeded) {
                        Add-LogEntry -Message "⏳ Azure token expiring soon, reauthenticating..." -Level WARNING -LogFilePath $LogFilePath
                        Connect-AzFederatedIdentity -LogFilePath $LogFilePath
                        $isAzureConnected = $true
                    }
                }
            }
        }
        else {
            Add-LogEntry -Message "⚠️ No valid Azure context detected." -Level WARNING -LogFilePath $LogFilePath
            if ($ReconnectIfNeeded) {
                Add-LogEntry -Message "🔁 Reconnecting to Azure via federated identity..." -Level INFO -LogFilePath $LogFilePath
                Connect-AzFederatedIdentity -LogFilePath $LogFilePath
                $isAzureConnected = $true
            }
        }
    }
    catch {
        Add-LogEntry -Message "❌ Error validating Azure connection: $($_.Exception.Message)" -Level ERROR -LogFilePath $LogFilePath
    }

    # --- Validate Microsoft Graph connection ---
    if ($TestGraph) {
        try {
            $graphContext = Get-MgContext -ErrorAction SilentlyContinue
            if ($graphContext -and $graphContext.Account) {
                Add-LogEntry -Message "✅ Microsoft Graph context found: $($graphContext.Account)" -Level SUCCESS -LogFilePath $LogFilePath
                $isGraphConnected = $true

                # Retrieve and decode Graph token
                $tokenResponse = az account get-access-token --resource https://graph.microsoft.com/ --output json | ConvertFrom-Json
                if ($tokenResponse.accessToken) {
                    $graphTokenInfo = Decode-JwtPayload -Jwt $tokenResponse.accessToken
                    if ($graphTokenInfo.exp) {
                        $expiry = [DateTimeOffset]::FromUnixTimeSeconds([int64]$graphTokenInfo.exp).ToLocalTime()
                        $remaining = ($expiry - (Get-Date)).TotalMinutes
                        Add-LogEntry -Message "🔑 Graph token expires at: $($expiry) ($([math]::Round($remaining,1)) minutes remaining)" -Level INFO -LogFilePath $LogFilePath
                        if ($remaining -le 10 -and $ReconnectIfNeeded) {
                            Add-LogEntry -Message "⏳ Graph token expiring soon, reauthenticating..." -Level WARNING -LogFilePath $LogFilePath
                            Connect-AzFederatedIdentity -UseGraphToken -LogFilePath $LogFilePath
                            $isGraphConnected = $true
                        }
                    }
                }
            }
            else {
                Add-LogEntry -Message "⚠️ No valid Microsoft Graph context detected." -Level WARNING -LogFilePath $LogFilePath
                if ($ReconnectIfNeeded) {
                    Add-LogEntry -Message "🔁 Reconnecting to Microsoft Graph via federated identity..." -Level INFO -LogFilePath $LogFilePath
                    Connect-AzFederatedIdentity -UseGraphToken -LogFilePath $LogFilePath
                    $isGraphConnected = $true
                }
            }
        }
        catch {
            Add-LogEntry -Message "❌ Error validating Graph connection: $($_.Exception.Message)" -Level ERROR -LogFilePath $LogFilePath
        }
    }

    # --- Summary ---
    Add-LogEntry -Message "Federated Connection Status Summary:" -Level INFO -LogFilePath $LogFilePath
    Add-LogEntry -Message "  Azure Connected: $isAzureConnected" -Level INFO -LogFilePath $LogFilePath
    Add-LogEntry -Message "  Graph Connected: $isGraphConnected" -Level INFO -LogFilePath $LogFilePath

    [PSCustomObject]@{
        AzureConnected = $isAzureConnected
        GraphConnected = $isGraphConnected
        AzureTokenExpiryMinutes = if ($azureTokenInfo.exp) { [math]::Round(($expiry - (Get-Date)).TotalMinutes,1) } else { $null }
        GraphTokenExpiryMinutes = if ($graphTokenInfo.exp) { [math]::Round(($expiry - (Get-Date)).TotalMinutes,1) } else { $null }
        Timestamp      = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
}