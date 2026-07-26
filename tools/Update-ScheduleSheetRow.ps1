#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
Updates one or more columns of a single row in the Schedule sheet, found by post_id.

.EXAMPLE
.\Update-ScheduleSheetRow.ps1 -PostId P0001 -Status AwaitingUserReview -Title "Sunset Over Santorini" -Hashtags "#travel #wanderlust" -ImagePath ".tmp/posts/P0001/image.png" -VideoPath ".tmp/posts/P0001/video.mp4"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PostId,
    [string]$Status,
    [string]$Title,
    [string]$Hashtags,
    [string]$ImagePath,
    [string]$VideoPath,
    [string]$Notes
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Common.ps1")

$token = Get-SheetAccessToken
$sheetId = Get-SheetId
$headers = @{ Authorization = "Bearer $token" }

$getUri = "https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/$([System.Uri]::EscapeDataString($Script:ScheduleRange))"
$response = Invoke-RestMethod -Uri $getUri -Headers $headers -Method Get
$rows = $response.values
if (-not $rows -or $rows.Count -lt 2) { throw "Schedule sheet is empty or missing a header row." }

$headerRow = $rows[0]
$colIndex = @{}
for ($c = 0; $c -lt $headerRow.Count; $c++) { $colIndex[[string]$headerRow[$c]] = $c }
if (-not $colIndex.ContainsKey("post_id")) { throw "post_id column not found in sheet header." }

$rowIndex = -1
for ($i = 1; $i -lt $rows.Count; $i++) {
    $row = $rows[$i]
    if ($row.Count -gt $colIndex["post_id"] -and $row[$colIndex["post_id"]] -eq $PostId) {
        $rowIndex = $i
        break
    }
}
if ($rowIndex -lt 0) { throw "post_id '$PostId' not found in Schedule sheet." }

$sheetRowNumber = $rowIndex + 1  # rows[] is 0-based, sheet is 1-based, header occupies row 1

$fieldsToUpdate = @{
    "status"     = $Status
    "title"      = $Title
    "hashtags"   = $Hashtags
    "image_path" = $ImagePath
    "video_path" = $VideoPath
    "notes"      = $Notes
}

$paramProvided = @{
    "status"     = $PSBoundParameters.ContainsKey("Status")
    "title"      = $PSBoundParameters.ContainsKey("Title")
    "hashtags"   = $PSBoundParameters.ContainsKey("Hashtags")
    "image_path" = $PSBoundParameters.ContainsKey("ImagePath")
    "video_path" = $PSBoundParameters.ContainsKey("VideoPath")
    "notes"      = $PSBoundParameters.ContainsKey("Notes")
}

$data = @()
foreach ($colName in $fieldsToUpdate.Keys) {
    if (-not $paramProvided[$colName]) { continue }
    if (-not $colIndex.ContainsKey($colName)) { throw "Column '$colName' not found in sheet header." }
    $colLetter = ConvertTo-ColumnLetter -Index $colIndex[$colName]
    $data += @{
        range  = "$($Script:ScheduleSheetName)!$colLetter$sheetRowNumber"
        values = @(, @($fieldsToUpdate[$colName]))
    }
}

if ($data.Count -eq 0) {
    Write-Output "No fields provided to update."
    return
}

$body = @{
    valueInputOption = "RAW"
    data             = $data
} | ConvertTo-Json -Depth 6

$updateUri = "https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values:batchUpdate"
Invoke-RestMethod -Uri $updateUri -Headers $headers -Method Post -Body $body -ContentType "application/json" | Out-Null

Write-Output "Updated post_id '$PostId' (row $sheetRowNumber): $($data.Count) field(s)."
