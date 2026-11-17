# Cache-aware buildx wrapper (Windows PowerShell). Linux twin: build.sh.
#
# Usage (from your project root, Dockerfile in place):
#   ./build.ps1                                    # CACHE_REF from .env or dir default
#   ./build.ps1 -ExtraArgs --platform linux/arm64  # extra buildx args
#   $env:CACHE_REF="ghcr.io/org/app:buildcache"; $env:PUSH="1"; ./build.ps1
#
# Config precedence: explicit env > .env (allowlisted keys only, literal
# values - never Invoke-Expression) > defaults. Default CACHE_REF is
# project-scoped: 127.0.0.1:5000/<dir>:buildcache.
#
# Keys: CACHE_REF, IMAGE, PUSH, DOCKERFILE, CONTEXT
[CmdletBinding()]
param(
    [string]$CacheRef = $env:CACHE_REF,
    [string]$Image = $env:IMAGE,
    [string]$Push = $(if ($null -ne $env:PUSH) { $env:PUSH } else { "0" }),
    [string]$Dockerfile = $(if ($null -ne $env:DOCKERFILE) { $env:DOCKERFILE } else { "Dockerfile" }),
    [string]$Context = $(if ($null -ne $env:CONTEXT) { $env:CONTEXT } else { "." }),
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs
)

$ErrorActionPreference = "Stop"

# .env (untrusted): allowlisted keys only, values taken literally.
if (Test-Path .env) {
    Get-Content .env | ForEach-Object {
        $k, $v = $_ -split '=', 2
        if ($k -and $v) {
            $v = $v.TrimEnd("`r")
            switch ($k.Trim()) {
                'CACHE_REF'  { if (-not $CacheRef)  { $CacheRef = $v } }
                'IMAGE'      { if (-not $Image)     { $Image = $v } }
                'PUSH'       { if ($Push -eq "0")   { $Push = $v } }
                'DOCKERFILE' { if ($Dockerfile -eq "Dockerfile") { $Dockerfile = $v } }
                'CONTEXT'    { if ($Context -eq ".") { $Context = $v } }
            }
        }
    }
}

if (-not $CacheRef) {
    $dir = Split-Path -Leaf (Get-Location)
    $CacheRef = "127.0.0.1:5000/${dir}:buildcache"
}
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
if ($ExtraArgs) { $bxArgs += $ExtraArgs }
$bxArgs += $Context

Write-Host "+ docker buildx $($bxArgs -join ' ')"
& docker buildx @bxArgs
exit $LASTEXITCODE
