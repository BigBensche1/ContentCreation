#Requires -Version 7.0
<#
.SYNOPSIS
Returns a fresh Google OAuth access token using the service account key (service-account.json).

.DESCRIPTION
Thin CLI wrapper around Common.ps1's New-GoogleServiceAccountAccessToken. Useful for
manually checking that service-account auth works, or for capturing a token directly:
    $token = & "$PSScriptRoot\Get-GoogleAccessToken.ps1"

See tools/Common.ps1's Get-ServiceAccountKeyPath for how the key file is located
(GOOGLE_SERVICE_ACCOUNT_KEY_PATH in .env, or service-account.json at the project root).
#>
[CmdletBinding()]
param(
    [string]$Scope = "https://www.googleapis.com/auth/spreadsheets"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Common.ps1")

Write-Output (New-GoogleServiceAccountAccessToken -Scope $Scope)
