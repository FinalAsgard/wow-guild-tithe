[CmdletBinding()]
param(
    [string]$WowRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repoRoot "AsgardsGuildTitheDev_Camelot.toc"
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Development manifest not found at '$manifestPath'. Run this script from the repository checkout."
}

if ([string]::IsNullOrWhiteSpace($WowRoot)) {
    $programFilesX86 = [Environment]::GetFolderPath("ProgramFilesX86")
    $WowRoot = Join-Path $programFilesX86 "World of Warcraft\_classic_beta_"
}

$resolvedWowRoot = Resolve-Path -LiteralPath $WowRoot -ErrorAction Stop
$addonsDirectory = Join-Path $resolvedWowRoot.Path "Interface\AddOns"
if (-not (Test-Path -LiteralPath $addonsDirectory -PathType Container)) {
    throw "WoW AddOns directory not found at '$addonsDirectory'. Pass -WowRoot with the correct client directory."
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

    Write-Host "Development add-on is already linked:"
    Write-Host "  $destination -> $repoPath"
    return
}

New-Item -ItemType Junction -Path $destination -Target $repoPath | Out-Null
Write-Host "Development add-on linked:"
Write-Host "  $destination -> $repoPath"
Write-Host "Restart WoW so it discovers Asgard's Guild Tithe (Dev)."
