#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
Sends the pre-publish review email (image + video attached) for one post, via Resend.

.DESCRIPTION
Uses the Resend transactional email API (RESEND_API_KEY, RESEND_FROM in .env) rather
than SMTP — Microsoft has disabled basic SMTP AUTH for personal Outlook/Hotmail accounts
account-wide, so direct SMTP send is not viable here regardless of password/app-password.

Approval is manual: the recipient reviews the attachments and then edits the post's
`status` cell in the Google Sheet to Approved or Rejected — this tool does not parse replies.

.EXAMPLE
.\Send-ReviewEmail.ps1 -PostId P0001 -Account example_instagram_account -Topic "Sunset in Santorini" `
    -Title "Golden Hour Over the Aegean" -Hashtags "#travel #wanderlust #explore" `
    -ImagePath ".tmp/posts/P0001/image.png" -VideoPath ".tmp/posts/P0001/video.mp4" `
    -ScheduledDateTime "2026-08-01 09:00"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PostId,
    [Parameter(Mandatory)][string]$Account,
    [string]$Topic,
    [string]$Title,
    [string]$Hashtags,
    [Parameter(Mandatory)][string]$ImagePath,
    [Parameter(Mandatory)][string]$VideoPath,
    [string]$ScheduledDateTime,
    [string]$ReviewNotes,
    [string]$To
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Common.ps1")
Import-DotEnv

foreach ($p in @($ImagePath, $VideoPath)) {
    if (-not (Test-Path $p)) { throw "Attachment not found: $p" }
}

$apiKey = $env:RESEND_API_KEY
$fromAddr = if ($env:RESEND_FROM) { $env:RESEND_FROM } else { "onboarding@resend.dev" }
$toAddr = if ($To) { $To } else { $env:REVIEW_EMAIL_TO }

foreach ($required in @(
    @{ Name = "RESEND_API_KEY"; Value = $apiKey }
    @{ Name = "REVIEW_EMAIL_TO (or -To)"; Value = $toAddr }
)) {
    if (-not $required.Value) { throw "$($required.Name) is not set. Fill it in .env." }
}

$subject = "Review needed: [$Account] $Title"

$body = @"
Post $PostId for account "$Account" is ready for your review.

Topic: $Topic
Proposed title: $Title
Hashtags: $Hashtags
Scheduled for: $ScheduledDateTime

Image review notes: $ReviewNotes

Image and video are attached.

To approve or reject: open the Schedule sheet and set the "status" cell for
post_id $PostId to "Approved" or "Rejected". The next pipeline run will act on it.
"@

function ConvertTo-ResendAttachment {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    @{
        filename = [System.IO.Path]::GetFileName($Path)
        content  = [Convert]::ToBase64String($bytes)
    }
}

$payload = @{
    from        = $fromAddr
    to          = @($toAddr)
    subject     = $subject
    text        = $body
    attachments = @(
        ConvertTo-ResendAttachment -Path $ImagePath
        ConvertTo-ResendAttachment -Path $VideoPath
    )
} | ConvertTo-Json -Depth 6

$headers = @{ Authorization = "Bearer $apiKey" }
$response = Invoke-RestMethod -Uri "https://api.resend.com/emails" -Method Post -Headers $headers -Body $payload -ContentType "application/json"

Write-Output "Review email sent to $toAddr for post_id $PostId (Resend id: $($response.id))."
