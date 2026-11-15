<#
.SYNOPSIS
    Bridge the kit's WSL2 engine to Windows-side tools: PowerShell docker CLI,
    VS Code Docker panel, Visual Studio, any Windows IDE.

.DESCRIPTION
    The kit's engine runs inside the distro; Windows-side docker CLI (Desktop's
    binary is fine - a context is client-side) talks to it over a LOOPBACK-ONLY
    TCP listener:
      1. systemd drop-in adds -H tcp://127.0.0.1:2375 to dockerd (inside the
         distro, as root)
      2. docker context 'kit-wsl' on Windows points at tcp://127.0.0.1:2375
      3. usage: docker --context kit-wsl ps  |  $env:DOCKER_HOST=...  | VS Code
         settings: "docker.host": "tcp://127.0.0.1:2375"

    SECURITY: the listener binds 127.0.0.1 ONLY, unauthenticated. That is the
    same trust boundary as docker-group membership (any local process can use
    it). Never expose it on 0.0.0.0; never forward it across machines.

    Kit mutation policy: -DryRun previews, -Yes unattended, -Undo reverses
    everything (drop-in + context).

.EXAMPLE
    ./setup/windows-context.ps1 -DryRun
    ./setup/windows-context.ps1                    # asks [y/N]
    ./setup/windows-context.ps1 -Yes -SetDefault
    ./setup/windows-context.ps1 -Undo
#>

[CmdletBinding()]
param(
    [string]$Distro = "Ubuntu-22.04",
    [switch]$SetDefault,
    [switch]$DryRun,
    [switch]$Yes,
    [switch]$Undo
)

$ErrorActionPreference = "Stop"

$DropInDir = "/etc/systemd/system/docker.service.d"
$DropInFile = "$DropInDir/kit-tcp.conf"
$Port = 2375

# --- distro presence -------------------------------------------------------------

$distros = @((wsl -l -q) 2>$null) | ForEach-Object { ($_ -replace "\x00", "").Trim() } | Where-Object { $_ }
if ($distros -notcontains $Distro) {
    throw "WSL distro '$Distro' not found (installed: $($distros -join ', '))."
}

# --- plan + consent ----------------------------------------------------------------

$plan = @"
Bridge plan (distro: $Distro):
  - systemd drop-in $DropInFile adds dockerd listener: tcp://127.0.0.1:$Port
  - restart docker inside the distro
  - Windows docker context 'kit-wsl' -> tcp://127.0.0.1:$Port
"@
if ($Undo) {
    $plan = @"
Undo plan (distro: $Distro):
  - remove $DropInFile, reload systemd, restart docker
  - delete the Windows docker context 'kit-wsl' (if present)
"@
}
if ($DryRun) {
    Write-Host "DRY-RUN: no changes will be made." -ForegroundColor Yellow
    Write-Host $plan
    Write-Host "DRY-RUN complete - nothing was changed." -ForegroundColor Yellow
    return
}
if (-not $Yes) {
    Write-Host $plan -ForegroundColor Cyan
    $answer = Read-Host "Proceed? [y/N]"
    if ($answer -notmatch '^[yY]') {
        throw "Aborted - no changes were made. Unattended: -Yes. Preview: -DryRun."
    }
}

# --- helper --------------------------------------------------------------------------

function Invoke-InDistro {
    param([string]$Bash)
    wsl -d $Distro -u root -- bash -c $Bash
}

$contextExists = $false
$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
if ($dockerCmd) {
    $contextExists = [bool](& docker context inspect kit-wsl 2>$null)
}

# --- undo ------------------------------------------------------------------------------

if ($Undo) {
    if ($DryRun) { return }
    Write-Host "Removing systemd drop-in..." -ForegroundColor Cyan
    Invoke-InDistro "rm -f '$DropInFile' && systemctl daemon-reload && systemctl restart docker"
    if ($dockerCmd) {
        Write-Host "Removing docker context 'kit-wsl'..." -ForegroundColor Cyan
        & docker context rm -f kit-wsl 2>$null
    }
    Write-Host "Undo complete. Windows-side docker goes back to its previous context." -ForegroundColor Green
    return
}

# --- in-distro: systemd drop-in + restart ------------------------------------------------

Write-Host "Adding TCP listener to dockerd (loopback only)..." -ForegroundColor Cyan
$inDistroDry = "echo '[DRY-RUN] would write $DropInFile'; echo '[DRY-RUN] would restart docker'"
if ($DryRun) {
    Invoke-InDistro $inDistroDry
} else {
    Invoke-InDistro ("mkdir -p '$DropInDir' && cat > '$DropInFile' <<'EOF'" + "`n" +
        "[Service]" + "`n" +
        "ExecStart=" + "`n" +
        "ExecStart=/usr/bin/dockerd -H fd -H tcp://127.0.0.1:$Port" + "`n" +
        "EOF`n" +
        "systemctl daemon-reload && systemctl restart docker")
}

# --- verify listener -----------------------------------------------------------------------

if (-not $DryRun) {
    Write-Host "Verifying the listener..." -ForegroundColor Cyan
    $probe = Invoke-InDistro ("docker -H tcp://127.0.0.1:$Port version --format '{{.Server.Version}}' 2>&1")
    if ($probe -notmatch '[0-9]') {
        throw "Listener verification failed: $probe - check systemctl status docker inside the distro."
    }
    Write-Host "Listener up (server $probe)." -ForegroundColor Green
}

# --- Windows side: docker context -------------------------------------------------------------

if (-not $dockerCmd) {
    Write-Warning "No docker CLI on Windows - install one (or use Docker Desktop's CLI), then:"
    Write-Host "  docker context create kit-wsl --docker `"host=tcp://127.0.0.1:$Port`"" -ForegroundColor Yellow
} else {
    if ($contextExists) {
        Write-Host "docker context 'kit-wsl' already exists." -ForegroundColor Green
    } elseif ($DryRun) {
        Write-Host "[DRY-RUN] docker context create kit-wsl --docker host=tcp://127.0.0.1:$Port" -ForegroundColor Yellow
    } else {
        & docker context create kit-wsl --docker "host=tcp://127.0.0.1:$Port" | Out-Null
        Write-Host "docker context 'kit-wsl' created." -ForegroundColor Green
    }
    if ($SetDefault -and -not $DryRun) {
        & docker context use kit-wsl | Out-Null
        Write-Host "Default context set to kit-wsl." -ForegroundColor Green
    }
}

# --- usage hints ---------------------------------------------------------------------------------

Write-Host ""
Write-Host "Done. Windows-side usage:" -ForegroundColor Green
Write-Host "  docker --context kit-wsl ps                        # one-off"
Write-Host "  `$env:DOCKER_HOST='tcp://127.0.0.1:$Port'           # per-session"
Write-Host '  VS Code settings: "docker.host": "tcp://127.0.0.1:2375"'
Write-Host "  Undo any time: ./setup/windows-context.ps1 -Undo"
