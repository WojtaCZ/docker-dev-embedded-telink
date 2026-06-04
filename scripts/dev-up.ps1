<#
.SYNOPSIS
    WSL shim — delegates to scripts/dev-up.sh running inside WSL2.
.DESCRIPTION
    Requires DEV_TELINK_SDK to point at the Telink_825X_SDK on the host,
    or place the SDK at ~/telink/Telink_825X_SDK (WSL home).
.EXAMPLE
    .\scripts\dev-up.ps1
    .\scripts\dev-up.ps1 -Workspace C:\code\ble_firmware -Rebuild
#>
[CmdletBinding()]
param(
    [string]$Workspace = (Get-Location).Path,
    [switch]$NoBuild,
    [switch]$NoPull,
    [switch]$Rebuild
)

$env:DEV_NO_BUILD = if ($NoBuild)  { "1" } else { "0" }
$env:DEV_NO_PULL  = if ($NoPull)   { "1" } else { "0" }
$env:DEV_REBUILD  = if ($Rebuild)  { "1" } else { "0" }

$wslWorkspace = wsl --exec wslpath -a $Workspace
wsl --cd "$PSScriptRoot/.." -- bash scripts/dev-up.sh $wslWorkspace
