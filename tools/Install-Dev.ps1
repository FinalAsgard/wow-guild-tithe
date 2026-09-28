[CmdletBinding()]
param(
    # Which supported client to link into. Forever stays the default.
    [ValidateSet("Forever", "Retail")]
    [string]$Client = "Forever",

    # The "World of Warcraft" folder that contains each client's directory.
    [string]$WowInstallRoot,

    # A specific client directory; overrides the one derived from -Client.
    [string]$WowRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$clients = @{
    Forever = @{ Directory = "_classic_beta_"; Manifest = "AsgardsGuildTitheDev_Camelot.toc" }
    Retail = @{ Directory = "_retail_"; Manifest = "AsgardsGuildTitheDev_Standard.toc" }
}
$target = $clients[$Client]

$repoRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repoRoot $target.Manifest
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "$Client development manifest not found at '$manifestPath'. Run this script from the repository checkout."
}

if ([string]::IsNullOrWhiteSpace($WowRoot)) {
    if ([string]::IsNullOrWhiteSpace($WowInstallRoot)) {
        $programFilesX86 = [Environment]::GetFolderPath("ProgramFilesX86")
        $WowInstallRoot = Join-Path $programFilesX86 "World of Warcraft"
    }
    $WowRoot = Join-Path $WowInstallRoot $target.Directory
}

$resolvedWowRoot = Resolve-Path -LiteralPath $WowRoot -ErrorAction Stop
$addonsDirectory = Join-Path $resolvedWowRoot.Path "Interface\AddOns"
if (-not (Test-Path -LiteralPath $addonsDirectory -PathType Container)) {
    throw "WoW AddOns directory not found at '$addonsDirectory'. Pass -WowRoot with the correct $Client client directory."
}

$destination = Join-Path $addonsDirectory "AsgardsGuildTitheDev"
$trimSeparators = [char[]]"\/"
$repoPath = [IO.Path]::GetFullPath($repoRoot).TrimEnd($trimSeparators)

if (Test-Path -LiteralPath $destination) {
    $existing = Get-Item -LiteralPath $destination -Force
    $isLink = ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    if (-not $isLink) {
        throw "'$destination' already exists and is not a junction. It was not changed."
    }

    $targets = @($existing.Target)
    if ($targets.Count -ne 1) {
        throw "'$destination' is a junction with an unreadable target. It was not changed."
    }

    $existingTarget = [IO.Path]::GetFullPath($targets[0]).TrimEnd($trimSeparators)
    if (-not [string]::Equals(
        $existingTarget,
        $repoPath,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "'$destination' points to '$existingTarget', not '$repoPath'. It was not changed."
    }

    Write-Host "Development add-on is already linked for ${Client}:"
    Write-Host "  $destination -> $repoPath"
    return
}

New-Item -ItemType Junction -Path $destination -Target $repoPath | Out-Null
Write-Host "Development add-on linked for ${Client}:"
Write-Host "  $destination -> $repoPath"
Write-Host "Restart WoW so it discovers Asgard's Guild Tithe (Dev)."
