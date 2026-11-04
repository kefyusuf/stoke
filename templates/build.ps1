# Cache-aware buildx wrapper (Windows PowerShell). Linux twin: build.sh.
#
# Usage (from your project root, Dockerfile in place):
#   $env:CACHE_REF="127.0.0.1:5000/myapp:buildcache"; ./templates/build.ps1
#   $env:CACHE_REF="ghcr.io/org/myapp:buildcache"; $env:PUSH="1"; ./templates/build.ps1
#
# Env:
#   CACHE_REF   registry ref for the BuildKit cache   (default: local registry)
#   IMAGE       tag for the built image               (optional)
#   PUSH        "1" pushes the image, otherwise --load
#   DOCKERFILE  path to Dockerfile                    (default Dockerfile)
#   CONTEXT     build context dir                     (default .)
[CmdletBinding()]
param(
    [string]$CacheRef = $env:CACHE_REF,
    [string]$Image = $env:IMAGE,
    [string]$Push = $(if ($null -ne $env:PUSH) { $env:PUSH } else { "0" }),
    [string]$Dockerfile = $(if ($null -ne $env:DOCKERFILE) { $env:DOCKERFILE } else { "Dockerfile" }),
    [string]$Context = $(if ($null -ne $env:CONTEXT) { $env:CONTEXT } else { "." })
)

$ErrorActionPreference = "Stop"

if (-not $CacheRef) { $CacheRef = "127.0.0.1:5000/myapp:buildcache" }
if (-not (Test-Path $Dockerfile)) { throw "Dockerfile not found: $Dockerfile" }
if ($Push -eq "1" -and -not $Image) { throw "PUSH=1 requires IMAGE=<registry/image:tag>" }

$bxArgs = @(
    "build",
    "--file", $Dockerfile,
    "--cache-from=type=registry,ref=$CacheRef",
    "--cache-to=type=registry,ref=$CacheRef,mode=max"
)

if ($Push -eq "1") {
    $bxArgs += "--push"
} else {
    $bxArgs += "--load"
}

if ($Image) { $bxArgs += @("-t", $Image) }
$bxArgs += $Context

Write-Host "+ docker buildx $($bxArgs -join ' ')"
& docker buildx @bxArgs
exit $LASTEXITCODE
