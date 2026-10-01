[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ProfilePath,
    [Parameter(Mandatory)][string[]]$SavePaths,
    [string]$GamePath = 'E:\Games\SteamLibrary\steamapps\common\Valheim',
    [switch]$Build
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if ($Build) {
    & (Join-Path $PSScriptRoot 'Build.ps1') -GamePath $GamePath
}
$pluginPath = Join-Path $projectRoot 'bin/Release/net48/OdinLookedAway.dll'
if (!(Test-Path -LiteralPath $pluginPath -PathType Leaf)) {
    throw 'Build Release first, or pass -Build.'
}
$pluginsDirectory = Join-Path (Resolve-Path -LiteralPath $ProfilePath).Path 'BepInEx/plugins'
if (!(Test-Path -LiteralPath $pluginsDirectory -PathType Container)) {
    throw "Not an existing BepInEx profile: $ProfilePath"
}
$installedPlugins = @(Get-ChildItem -LiteralPath $pluginsDirectory -Filter 'OdinLookedAway.dll' -File -Recurse)
if ($installedPlugins.Count -gt 1) {
    throw 'Multiple OdinLookedAway DLLs are installed; resolve duplicates first.'
}
$targetPluginPath = if ($installedPlugins.Count -eq 1) {
    $installedPlugins[0].FullName
}
else {
    Join-Path $pluginsDirectory 'OdinLookedAway/OdinLookedAway.dll'
}
if (!$PSCmdlet.ShouldProcess($targetPluginPath, 'Back up saves/plugin and deploy OdinLookedAway')) {
    return
}
if (Get-Process -Name valheim, valheim_server -ErrorAction SilentlyContinue) {
    throw 'Close Valheim and dedicated servers before deploying.'
}
$backupDirectory = Join-Path $projectRoot ('.local/rollback/' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))

# Finish both backups before replacing the DLL. Record its absence on a new install.
& (Join-Path $PSScriptRoot 'Backup-Saves.ps1') -SavePaths $SavePaths -Destination $backupDirectory
$hadPreviousPlugin = Test-Path -LiteralPath $targetPluginPath -PathType Leaf
$previousPluginHash = $null
if ($hadPreviousPlugin) {
    $previousPluginHash = (Get-FileHash -LiteralPath $targetPluginPath).Hash
    Copy-Item -LiteralPath $targetPluginPath -Destination (Join-Path $backupDirectory 'previous-plugin.dll')
    if ((Get-FileHash -LiteralPath (Join-Path $backupDirectory 'previous-plugin.dll')).Hash -ne $previousPluginHash) {
        throw 'Plugin backup verification failed.'
    }
}
$deployedPluginHash = (Get-FileHash -LiteralPath $pluginPath).Hash
[ordered]@{
    target       = $targetPluginPath
    existed      = $hadPreviousPlugin
    oldHash      = $previousPluginHash
    deployedHash = $deployedPluginHash
} |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backupDirectory 'plugin.json') -Encoding utf8
New-Item -ItemType Directory -Path (Split-Path $targetPluginPath -Parent) -Force | Out-Null

try {
    Copy-Item -LiteralPath $pluginPath -Destination $targetPluginPath -Force
    if ((Get-FileHash -LiteralPath $targetPluginPath).Hash -ne $deployedPluginHash) {
        throw 'Deployment verification failed.'
    }
}
catch {
    # Undo the DLL copy on failure. Save files have not been touched.
    if ($hadPreviousPlugin) {
        Copy-Item -LiteralPath (Join-Path $backupDirectory 'previous-plugin.dll') -Destination $targetPluginPath -Force
    }
    elseif (Test-Path -LiteralPath $targetPluginPath) {
        Remove-Item -LiteralPath $targetPluginPath
    }
    throw
}
Write-Host "Deployed: $targetPluginPath"
Write-Host "Rollback directory: $backupDirectory"
