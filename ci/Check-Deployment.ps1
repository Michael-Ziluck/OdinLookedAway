[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$fixtureDirectory = Join-Path $projectRoot ('.local/deploy-checks/' + [guid]::NewGuid().ToString('N'))
$profileDirectory = Join-Path $fixtureDirectory 'profile'
$saveDirectory = Join-Path $fixtureDirectory 'saves'
New-Item -ItemType Directory -Path (Join-Path $profileDirectory 'BepInEx/plugins/OdinLookedAway'), $saveDirectory -Force | Out-Null
$pluginPath = Join-Path $profileDirectory 'BepInEx/plugins/OdinLookedAway/OdinLookedAway.dll'
$savePath = Join-Path $saveDirectory 'disposable.fch'
[IO.File]::WriteAllText($savePath, 'original test save')
[IO.File]::WriteAllText($pluginPath, 'previous test plugin')
# Only disposable fixture paths reach Deploy/Rollback. Let these checks run while
# Valheim is open without bypassing the process check in a real deployment.
function Get-Process {
    [CmdletBinding()]
    param([string[]]$Name)
}

function Assert-DeploymentCheck {
    param([bool]$Condition, [string]$Message)

    if (!$Condition) {
        throw $Message
    }
}

$backupRoot = Join-Path $projectRoot '.local/rollback'
$existingBackups = @(Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object FullName)
& (Join-Path $PSScriptRoot 'Deploy.ps1') -ProfilePath $profileDirectory -SavePaths $saveDirectory -WhatIf
Assert-DeploymentCheck ((Get-Content -LiteralPath $pluginPath -Raw) -eq 'previous test plugin') 'WhatIf changed the plugin.'

& (Join-Path $PSScriptRoot 'Deploy.ps1') -ProfilePath $profileDirectory -SavePaths $saveDirectory
$newBackups = @(Get-ChildItem -LiteralPath $backupRoot -Directory | Where-Object { $_.FullName -notin $existingBackups })
Assert-DeploymentCheck ($newBackups.Count -eq 1) 'Expected exactly one verified rollback.'
$pluginBackup = Get-Content -LiteralPath (Join-Path $newBackups[0].FullName 'plugin.json') -Raw | ConvertFrom-Json
Assert-DeploymentCheck ($pluginBackup.target -eq $pluginPath) 'Rollback unexpectedly points outside the fixture.'
Assert-DeploymentCheck ((Get-FileHash -LiteralPath $pluginPath).Hash -eq (Get-FileHash -LiteralPath (Join-Path $projectRoot 'bin/Release/net48/OdinLookedAway.dll')).Hash) 'Deployed DLL mismatch.'
[IO.File]::WriteAllText($savePath, 'changed test save')
& (Join-Path $PSScriptRoot 'Rollback.ps1') -BackupDirectory $newBackups[0].FullName -RestoreSaves
Assert-DeploymentCheck ((Get-Content -LiteralPath $savePath -Raw) -eq 'original test save') 'Save rollback failed.'
Assert-DeploymentCheck ((Get-Content -LiteralPath $pluginPath -Raw) -eq 'previous test plugin') 'Plugin rollback failed.'

# New-install rollback must remove only the verified deployed DLL.
Remove-Item -LiteralPath $pluginPath
$existingBackups = @(Get-ChildItem -LiteralPath $backupRoot -Directory | ForEach-Object FullName)
& (Join-Path $PSScriptRoot 'Deploy.ps1') -ProfilePath $profileDirectory -SavePaths $saveDirectory
$newBackups = @(Get-ChildItem -LiteralPath $backupRoot -Directory | Where-Object { $_.FullName -notin $existingBackups })
Assert-DeploymentCheck ($newBackups.Count -eq 1) 'New installation did not produce one rollback.'
$pluginBackup = Get-Content -LiteralPath (Join-Path $newBackups[0].FullName 'plugin.json') -Raw | ConvertFrom-Json
Assert-DeploymentCheck ($pluginBackup.target -eq $pluginPath) 'Rollback unexpectedly points outside the fixture.'
& (Join-Path $PSScriptRoot 'Rollback.ps1') -BackupDirectory $newBackups[0].FullName
Assert-DeploymentCheck (!(Test-Path -LiteralPath $pluginPath)) 'New-install rollback did not remove the mod.'
Write-Host 'PASS: fixture-only deployment preview, save/plugin backup hashes, replacement rollback, save restoration, and new-install removal.'
