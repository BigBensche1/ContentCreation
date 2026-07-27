#Requires -Version 7.0
<#
.SYNOPSIS
Shared helpers dot-sourced by the schedule-sheet tools. Not meant to be run directly.
Requires PowerShell 7+ (uses RSA.ImportFromPem for Google service-account JWT signing).
#>

function Import-DotEnv {
    param([string]$Path = (Join-Path $PSScriptRoot ".." ".env"))
    if (-not (Test-Path $Path)) { return }
    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $idx = $line.IndexOf("=")
            $key = $line.Substring(0, $idx).Trim()
            $value = $line.Substring($idx + 1).Trim()
            [System.Environment]::SetEnvironmentVariable($key, $value, "Process")
        }
    }
}

$Script:ScheduleColumns = @("post_id", "account", "topic", "scheduled_datetime", "status", "title", "hashtags", "image_path", "video_path", "notes")
$Script:ScheduleSheetName = "Schedule"
$Script:ScheduleRange = "Schedule!A:J"

function Get-SheetAccessToken {
    New-GoogleServiceAccountAccessToken -Scope "https://www.googleapis.com/auth/spreadsheets"
}

function Get-SheetId {
    Import-DotEnv
    $id = $env:GOOGLE_SHEET_ID
    if (-not $id) { throw "GOOGLE_SHEET_ID not set in .env" }
    return $id
}

function ConvertTo-ColumnLetter {
    param([int]$Index) # 0-based
    [char](65 + $Index)
}

function Get-ServiceAccountKeyPath {
    Import-DotEnv
    $path = if ($env:GOOGLE_SERVICE_ACCOUNT_KEY_PATH) { $env:GOOGLE_SERVICE_ACCOUNT_KEY_PATH } else { Join-Path $PSScriptRoot ".." "service-account.json" }
    if (-not (Test-Path $path)) {
        throw "Service account key not found at '$path'. Create one in Google Cloud Console (IAM & Admin > Service Accounts > Keys > Add key > JSON), save it there (or point GOOGLE_SERVICE_ACCOUNT_KEY_PATH at it in .env), and share the target Google Sheet with its client_email as an Editor."
    }
    return $path
}

function ConvertTo-Base64Url {
    param([byte[]]$Bytes)
    [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function New-GoogleServiceAccountAccessToken {
    param(
        [string]$Scope = "https://www.googleapis.com/auth/spreadsheets"
    )

    $keyPath = Get-ServiceAccountKeyPath
    $key = Get-Content $keyPath -Raw | ConvertFrom-Json
    foreach ($field in @("client_email", "private_key", "token_uri")) {
        if (-not $key.$field) { throw "Service account key at '$keyPath' is missing '$field'." }
    }

    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $exp = $now + 3600

    $header = @{ alg = "RS256"; typ = "JWT" } | ConvertTo-Json -Compress
    $claims = @{
        iss   = $key.client_email
        scope = $Scope
        aud   = $key.token_uri
        iat   = $now
        exp   = $exp
    } | ConvertTo-Json -Compress

    $headerB64 = ConvertTo-Base64Url ([System.Text.Encoding]::UTF8.GetBytes($header))
    $claimsB64 = ConvertTo-Base64Url ([System.Text.Encoding]::UTF8.GetBytes($claims))
    $signingInput = "$headerB64.$claimsB64"

    $rsa = [System.Security.Cryptography.RSA]::Create()
    try {
        $rsa.ImportFromPem($key.private_key)
        $signatureBytes = $rsa.SignData(
            [System.Text.Encoding]::UTF8.GetBytes($signingInput),
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        )
    } finally {
        $rsa.Dispose()
    }
    $signatureB64 = ConvertTo-Base64Url $signatureBytes

    $jwt = "$signingInput.$signatureB64"

    $body = @{
        grant_type = "urn:ietf:params:oauth:grant-type:jwt-bearer"
        assertion  = $jwt
    }

    $response = Invoke-RestMethod -Uri $key.token_uri -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
    if (-not $response.access_token) {
        throw "Service account token exchange did not return an access_token: $($response | ConvertTo-Json -Compress)"
    }

    return $response.access_token
}
