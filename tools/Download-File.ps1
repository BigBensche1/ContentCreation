#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
Downloads a URL (e.g. a Higgsfield generation result) to a local file, creating parent folders as needed.

.EXAMPLE
.\Download-File.ps1 -Url "https://cdn.higgsfield.ai/.../image.png" -OutFile ".tmp/posts/P0001/image.png"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Url,
    [Parameter(Mandatory)][string]$OutFile
)

$ErrorActionPreference = "Stop"

$parent = Split-Path -Parent $OutFile
if ($parent -and -not (Test-Path $parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
}

Invoke-WebRequest -Uri $Url -OutFile $OutFile

if (-not (Test-Path $OutFile)) {
    throw "Download appeared to succeed but '$OutFile' does not exist."
}

$size = (Get-Item $OutFile).Length
Write-Output "Downloaded $Url -> $OutFile ($size bytes)"
