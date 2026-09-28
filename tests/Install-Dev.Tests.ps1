# Exercises tools/Install-Dev.ps1 against throwaway Forever and Retail layouts.
# Run from the repository root on Windows: pwsh ./tests/Install-Dev.Tests.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $repoRoot "tools\Install-Dev.ps1"
$trimSeparators = [char[]]"\/"
$repoPath = [IO.Path]::GetFullPath($repoRoot).TrimEnd($trimSeparators)
$scratch = Join-Path ([IO.Path]::GetTempPath()) ("agt-install-" + [Guid]::NewGuid().ToString("N"))
$failures = 0

function New-ClientRoot([string]$Path) {
    New-Item -ItemType Directory -Path (Join-Path $Path "Interface\AddOns") -Force | Out-Null
    return $Path
}

function Get-DevDestination([string]$ClientRoot) {
    return Join-Path $ClientRoot "Interface\AddOns\AsgardsGuildTitheDev"
}

function Assert-LinkedToRepo([string]$ClientRoot) {
    $item = Get-Item -LiteralPath (Get-DevDestination $ClientRoot) -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
        throw "Development install at '$ClientRoot' is not a junction."
    }
    $linked = [IO.Path]::GetFullPath(@($item.Target)[0]).TrimEnd($trimSeparators)
    if (-not [string]::Equals($linked, $repoPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Development install at '$ClientRoot' points to '$linked', not '$repoPath'."
    }
}

function Assert-Refused([scriptblock]$Install, [string]$Reason) {
    $refused = $false
    try {
        & $Install *> $null
    } catch {
        $refused = $true
    }
    if (-not $refused) {
        throw "Installer did not refuse: $Reason"
    }
}

function Test-Case([string]$Name, [scriptblock]$Body) {
    try {
        & $Body
        Write-Host "PASS $Name"
    } catch {
        $script:failures++
        Write-Host "FAIL $Name"
        Write-Host "  $_"
    }
}

New-Item -ItemType Directory -Path $scratch | Out-Null
try {
    Test-Case "default client links Forever under the install root and is idempotent" {
        $installRoot = Join-Path $scratch "default\World of Warcraft"
        $forever = New-ClientRoot (Join-Path $installRoot "_classic_beta_")
        $retail = New-ClientRoot (Join-Path $installRoot "_retail_")

        & $installer -WowInstallRoot $installRoot | Out-Null
        & $installer -WowInstallRoot $installRoot | Out-Null

        Assert-LinkedToRepo $forever
        if (Test-Path -LiteralPath (Get-DevDestination $retail)) {
            throw "Default install also linked Retail."
        }
    }

    Test-Case "explicit Forever matches the default layout" {
        $installRoot = Join-Path $scratch "forever\World of Warcraft"
        $forever = New-ClientRoot (Join-Path $installRoot "_classic_beta_")

        & $installer -Client Forever -WowInstallRoot $installRoot | Out-Null

        Assert-LinkedToRepo $forever
    }

    Test-Case "Retail links under _retail_ and is idempotent" {
        $installRoot = Join-Path $scratch "retail\World of Warcraft"
        $forever = New-ClientRoot (Join-Path $installRoot "_classic_beta_")
        $retail = New-ClientRoot (Join-Path $installRoot "_retail_")

        & $installer -Client Retail -WowInstallRoot $installRoot | Out-Null
        & $installer -Client Retail -WowInstallRoot $installRoot | Out-Null

        Assert-LinkedToRepo $retail
        if (Test-Path -LiteralPath (Get-DevDestination $forever)) {
            throw "Retail install also linked Forever."
        }
    }

    Test-Case "explicit -WowRoot overrides the derived client directory" {
        $custom = New-ClientRoot (Join-Path $scratch "custom\Games\Retail")

        & $installer -Client Retail -WowRoot $custom | Out-Null
        & $installer -Client Retail -WowRoot $custom | Out-Null

        Assert-LinkedToRepo $custom
    }

    Test-Case "a junction to another checkout is refused and left unchanged" {
        foreach ($client in "Forever", "Retail") {
            $root = New-ClientRoot (Join-Path $scratch "conflict-$client")
            $otherCheckout = Join-Path $scratch "other-checkout-$client"
            New-Item -ItemType Directory -Path $otherCheckout | Out-Null
            $destination = Get-DevDestination $root
            New-Item -ItemType Junction -Path $destination -Target $otherCheckout | Out-Null

            Assert-Refused { & $installer -Client $client -WowRoot $root } "$client conflicting junction"

            $linked = [IO.Path]::GetFullPath(@((Get-Item -LiteralPath $destination -Force).Target)[0]).TrimEnd($trimSeparators)
            if (-not [string]::Equals($linked, $otherCheckout.TrimEnd($trimSeparators), [StringComparison]::OrdinalIgnoreCase)) {
                throw "$client conflicting junction was retargeted to '$linked'."
            }
        }
    }

    Test-Case "a real directory is refused and left unchanged" {
        foreach ($client in "Forever", "Retail") {
            $root = New-ClientRoot (Join-Path $scratch "blocked-$client")
            $destination = Get-DevDestination $root
            New-Item -ItemType Directory -Path $destination | Out-Null
            $marker = Join-Path $destination "keep.txt"
            Set-Content -LiteralPath $marker -Value "real directory"

            Assert-Refused { & $installer -Client $client -WowRoot $root } "$client real directory"

            $item = Get-Item -LiteralPath $destination -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "$client real directory was replaced by a junction."
            }
            if ((Get-Content -LiteralPath $marker) -ne "real directory") {
                throw "$client real directory contents changed."
            }
        }
    }

    Test-Case "a client directory without Interface\AddOns is refused" {
        $root = Join-Path $scratch "no-addons\_retail_"
        New-Item -ItemType Directory -Path $root -Force | Out-Null

        Assert-Refused { & $installer -Client Retail -WowRoot $root } "missing AddOns directory"
    }
} finally {
    Get-ChildItem -LiteralPath $scratch -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Delete() }
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures -gt 0) {
    throw "$failures installer test(s) failed."
}
Write-Host "All installer tests passed."
