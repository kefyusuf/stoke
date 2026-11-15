<#
.SYNOPSIS
    Windows-side bootstrap for stoke: WSL2, a distro, and .wslconfig.

.DESCRIPTION
    - Installs WSL2 (without a distro) if missing, then installs $Distro.
    - Writes %UserProfile%\.wslconfig from the given limits (backs up an existing file).
    - Shuts WSL down so the new limits apply at next start.
    Run from an *administrator* PowerShell. Reboot if WSL installation asks for one.
    Kit-wide mutation policy: -DryRun previews every change without applying;
    -Yes skips the consent prompt for unattended runs.

.EXAMPLE
    ./setup/setup-wsl.ps1
    ./setup/setup-wsl.ps1 -DryRun
    ./setup/setup-wsl.ps1 -Yes -Distro Ubuntu-22.04 -MemoryGB 8 -Processors 6
#>

[CmdletBinding()]
param(
    [string]$Distro = "Ubuntu-22.04",
    [int]$MemoryGB = 6,
    [int]$Processors = 4,
    [int]$SwapGB = 2,
    [string]$WslConfigPath = "$env:USERPROFILE\.wslconfig",
    [switch]$SkipWslConfig,
    [switch]$DryRun,
    [switch]$Yes
)

$ErrorActionPreference = "Stop"

# --- admin check -------------------------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Please run from an administrator PowerShell (WSL feature installation needs elevation)."
}

# --- consent (kit-wide mutation policy) ----------------------------------------
if ($DryRun) {
    Write-Host "DRY-RUN: no changes will be made." -ForegroundColor Yellow
} elseif (-not $Yes) {
    Write-Host "Plan: WSL2 bootstrap - Windows features, distro '$Distro', $WslConfigPath (backed up if present)." -ForegroundColor Cyan
    $answer = Read-Host "Proceed? [y/N]"
    if ($answer -notmatch '^[yY]') {
        throw "Aborted - no changes were made. Unattended: -Yes. Preview: -DryRun."
    }
}

# --- WSL presence ------------------------------------------------------------
$wslCmd = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wslCmd) {
    if ($DryRun) {
        Write-Host "[DRY-RUN] wsl --install --no-distribution" -ForegroundColor Yellow
    } else {
        Write-Host "WSL not found - installing WSL2 (no distro yet)..." -ForegroundColor Cyan
        wsl --install --no-distribution
        if ($LASTEXITCODE -ne 0) { throw "wsl --install failed. A reboot is likely required - reboot and re-run this script." }
        Write-Warning "WSL was installed. If this is the first time, REBOOT, then re-run this script."
    }
} else {
    Write-Host "WSL already installed." -ForegroundColor Green
}

# --- distro ------------------------------------------------------------------
# wsl -l -q outputs UTF-16 on some builds -> strip null chars defensively.
$distros = @((wsl -l -q) 2>$null) | ForEach-Object { ($_ -replace "\x00", "").Trim() } | Where-Object { $_ }
$installed = $distros | Where-Object { $_ -eq $Distro }
if (-not $installed) {
    if ($DryRun) {
        Write-Host "[DRY-RUN] wsl --install -d $Distro --no-launch" -ForegroundColor Yellow
    } else {
        Write-Host "Installing distro '$Distro' (no launch)..." -ForegroundColor Cyan
        wsl --install -d $Distro --no-launch
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Available distros:" -ForegroundColor Yellow
            wsl --list --online
            throw "wsl --install -d $Distro failed. Pick a distro from the list above."
        }
    }
} else {
    Write-Host "Distro '$Distro' already installed." -ForegroundColor Green
}

# --- .wslconfig ---------------------------------------------------------------
if ($SkipWslConfig) {
    Write-Host "Skipping .wslconfig (-SkipWslConfig)." -ForegroundColor Yellow
} elseif ($DryRun) {
    Write-Host "[DRY-RUN] would back up (if present) and write $WslConfigPath (memory=${MemoryGB}GB, processors=$Processors, swap=${SwapGB}GB, autoMemoryReclaim=gradual, sparseVhd=true)" -ForegroundColor Yellow
} else {
    if (Test-Path $WslConfigPath) {
        $backup = "$WslConfigPath.bak.$(Get-Date -Format yyyyMMdd-HHmmss)"
        Copy-Item $WslConfigPath $backup
        Write-Host "Existing .wslconfig backed up to $backup" -ForegroundColor Yellow
    }

    $content = @"
[wsl2]
# Hard cap for the WSL2 utility VM (Task Manager shows it as "VMMEM").
# Rule of thumb: 1/3 - 1/2 of host RAM. See setup/.wslconfig.template for notes.
memory=${MemoryGB}GB
processors=$Processors
swap=${SwapGB}GB

[experimental]
# Return idle cached memory to Windows (WSL 2.0+).
autoMemoryReclaim=gradual
# Shrink the ext4 virtual disk after deletions (WSL 2.0+).
sparseVhd=true
"@
    Set-Content -Path $WslConfigPath -Value $content -Encoding ASCII
    Write-Host "Wrote $WslConfigPath" -ForegroundColor Green
}

# --- apply --------------------------------------------------------------------
if ($DryRun) {
    Write-Host "[DRY-RUN] wsl --shutdown (to apply settings at next start)" -ForegroundColor Yellow
} else {
    Write-Host "Shutting down WSL so settings apply at next start..." -ForegroundColor Cyan
    wsl --shutdown 2>$null
}

if ($DryRun) {
    Write-Host "DRY-RUN complete - nothing was changed." -ForegroundColor Yellow
    return
}

Write-Host ""
Write-Host "Done. Next steps:" -ForegroundColor Green
Write-Host "  1. Open the '$Distro' terminal (Start menu or: wsl -d $Distro)"
Write-Host "  2. Clone this repo INSIDE the distro (e.g. ~/work/stoke), NOT under /mnt/c"
Write-Host "  3. ./setup/setup-engine.sh"
