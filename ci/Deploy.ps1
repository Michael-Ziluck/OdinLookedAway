[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ProfilePath,
    [Parameter(Mandatory)][string[]]$SavePaths,
    [string]$GamePath = 'E:\Games\SteamLibrary\steamapps\common\Valheim',
    [switch]$Build
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if ($Build) { & (Join-Path $PSScriptRoot 'Build.ps1') -GamePath $GamePath }
$dll = Join-Path $root 'bin/Release/net48/OdinLookedAway.dll'
if (!(Test-Path -LiteralPath $dll -PathType Leaf)) { throw 'Build Release first, or pass -Build.' }
$plugins = Join-Path (Resolve-Path -LiteralPath $ProfilePath).Path 'BepInEx/plugins'
if (!(Test-Path -LiteralPath $plugins -PathType Container)) { throw "Not an existing BepInEx profile: $ProfilePath" }
$installed = @(Get-ChildItem -LiteralPath $plugins -Filter 'OdinLookedAway.dll' -File -Recurse)
if ($installed.Count -gt 1) { throw 'Multiple OdinLookedAway DLLs are installed; resolve duplicates first.' }
$target = if ($installed.Count -eq 1) { $installed[0].FullName } else { Join-Path $plugins 'OdinLookedAway/OdinLookedAway.dll' }
if (!$PSCmdlet.ShouldProcess($target, 'Back up saves/plugin and deploy OdinLookedAway')) { return }
if (Get-Process -Name valheim,valheim_server -ErrorAction SilentlyContinue) { throw 'Close Valheim and dedicated servers before deploying.' }
$backup = Join-Path $root ('.local/rollback/' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
& (Join-Path $PSScriptRoot 'Backup-Saves.ps1') -SavePaths $SavePaths -Destination $backup
$previous = Test-Path -LiteralPath $target -PathType Leaf
$oldHash = $null
if ($previous) {
    $oldHash = (Get-FileHash -LiteralPath $target).Hash
    Copy-Item -LiteralPath $target -Destination (Join-Path $backup 'previous-plugin.dll')
    if ((Get-FileHash -LiteralPath (Join-Path $backup 'previous-plugin.dll')).Hash -ne $oldHash) { throw 'Plugin backup verification failed.' }
}
$newHash = (Get-FileHash -LiteralPath $dll).Hash
[ordered]@{ target = $target; existed = $previous; oldHash = $oldHash; deployedHash = $newHash } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backup 'plugin.json') -Encoding utf8
New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
try {
    Copy-Item -LiteralPath $dll -Destination $target -Force
    if ((Get-FileHash -LiteralPath $target).Hash -ne $newHash) { throw 'Deployment verification failed.' }
} catch {
    if ($previous) { Copy-Item -LiteralPath (Join-Path $backup 'previous-plugin.dll') -Destination $target -Force }
    elseif (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target }
    throw
}
Write-Host "Deployed: $target"
Write-Host "Rollback directory: $backup"
