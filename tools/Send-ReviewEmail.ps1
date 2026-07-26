#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
Sends the pre-publish review email (image + video attached) for one post.

.DESCRIPTION
Reads SMTP settings from .env (SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS,
REVIEW_EMAIL_FROM, REVIEW_EMAIL_TO). Approval is manual: the recipient reviews
the attachments and then edits the post's `status` cell in the Google Sheet to
Approved or Rejected — this tool does not parse replies.

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

$smtpHost = $env:SMTP_HOST
$smtpPort = $env:SMTP_PORT
$smtpUser = $env:SMTP_USER
$smtpPass = $env:SMTP_PASS
$fromAddr = if ($env:REVIEW_EMAIL_FROM) { $env:REVIEW_EMAIL_FROM } else { $smtpUser }
$toAddr = if ($To) { $To } else { $env:REVIEW_EMAIL_TO }

foreach ($required in @(
    @{ Name = "SMTP_HOST"; Value = $smtpHost }
    @{ Name = "SMTP_PORT"; Value = $smtpPort }
    @{ Name = "SMTP_USER"; Value = $smtpUser }
    @{ Name = "SMTP_PASS"; Value = $smtpPass }
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

$securePass = ConvertTo-SecureString $smtpPass -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($smtpUser, $securePass)

Send-MailMessage -From $fromAddr -To $toAddr -Subject $subject -Body $body `
    -SmtpServer $smtpHost -Port $smtpPort -UseSsl -Credential $cred `
    -Attachments @($ImagePath, $VideoPath)

Write-Output "Review email sent to $toAddr for post_id $PostId."
