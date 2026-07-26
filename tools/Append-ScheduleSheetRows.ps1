#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
Appends one or more new rows to the Schedule sheet. Used by the weekly content-planning workflow.

.PARAMETER RowsJson
A JSON array of objects, each with any subset of the schedule columns
(post_id, account, topic, scheduled_datetime, status, title, hashtags, image_path, video_path, notes).
Missing columns are written as blank.

.PARAMETER RowsJsonPath
Alternative to -RowsJson: path to a file containing the same JSON array.

.EXAMPLE
.\Append-ScheduleSheetRows.ps1 -RowsJson '[{"post_id":"P0010","account":"example_instagram_account","topic":"Hidden waterfalls in Iceland","scheduled_datetime":"2026-08-03 09:00","status":"Pending","notes":"auto-scheduled from trend research: Iceland waterfall reels trending this week"}]'
#>
[CmdletBinding(DefaultParameterSetName = "Inline")]
param(
    [Parameter(Mandatory, ParameterSetName = "Inline")][string]$RowsJson,
    [Parameter(Mandatory, ParameterSetName = "FromFile")][string]$RowsJsonPath
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Common.ps1")

if ($PSCmdlet.ParameterSetName -eq "FromFile") {
    if (-not (Test-Path $RowsJsonPath)) { throw "File not found: $RowsJsonPath" }
    $RowsJson = Get-Content $RowsJsonPath -Raw
}

$rowObjects = $RowsJson | ConvertFrom-Json
if ($rowObjects -isnot [System.Collections.IEnumerable] -or $rowObjects -is [string]) {
    $rowObjects = @($rowObjects)
}

$values = @()
foreach ($obj in $rowObjects) {
    $rowArray = @()
    foreach ($col in $Script:ScheduleColumns) {
        $val = $obj.$col
        if ($null -eq $val) { $val = "" }
        $rowArray += [string]$val
    }
    $values += , $rowArray
}

if ($values.Count -eq 0) {
    Write-Output "No rows to append."
    return
}

$token = Get-SheetAccessToken
$sheetId = Get-SheetId
$headers = @{ Authorization = "Bearer $token" }

$appendUri = "https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/$([System.Uri]::EscapeDataString($Script:ScheduleRange)):append?valueInputOption=RAW&insertDataOption=INSERT_ROWS"

$body = @{ values = $values } | ConvertTo-Json -Depth 6

$response = Invoke-RestMethod -Uri $appendUri -Headers $headers -Method Post -Body $body -ContentType "application/json"

Write-Output "Appended $($values.Count) row(s) to Schedule. Range: $($response.updates.updatedRange)"
