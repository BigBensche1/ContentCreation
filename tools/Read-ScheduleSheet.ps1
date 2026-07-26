#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
Reads the Schedule tab of the Google Sheet and prints rows as JSON.

.PARAMETER DueOnly
Only return rows whose status is blank/"Pending" and scheduled_datetime <= now.

.EXAMPLE
.\Read-ScheduleSheet.ps1 -DueOnly
#>
[CmdletBinding()]
param(
    [switch]$DueOnly
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Common.ps1")

$token = Get-SheetAccessToken
$sheetId = Get-SheetId
$headers = @{ Authorization = "Bearer $token" }

$uri = "https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/$([System.Uri]::EscapeDataString($Script:ScheduleRange))"
$response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get

$rows = $response.values
if (-not $rows -or $rows.Count -lt 2) {
    Write-Output "[]"
    return
}

$headerRow = $rows[0]
$results = @()
for ($i = 1; $i -lt $rows.Count; $i++) {
    $row = $rows[$i]
    $obj = [ordered]@{}
    for ($c = 0; $c -lt $headerRow.Count; $c++) {
        $obj[[string]$headerRow[$c]] = if ($c -lt $row.Count) { $row[$c] } else { "" }
    }
    $obj["_row_number"] = $i + 1  # 1-based sheet row (header is row 1)
    $results += [PSCustomObject]$obj
}

if ($DueOnly) {
    $now = Get-Date
    $results = $results | Where-Object {
        ($_.status -eq "" -or $_.status -eq "Pending") -and
        $_.scheduled_datetime -and
        ([datetime]::Parse($_.scheduled_datetime) -le $now)
    }
}

$resultsArray = @($results)
if ($resultsArray.Count -eq 0) {
    Write-Output "[]"
} elseif ($resultsArray.Count -eq 1) {
    Write-Output "[$($resultsArray[0] | ConvertTo-Json -Depth 5)]"
} else {
    $resultsArray | ConvertTo-Json -Depth 5
}
