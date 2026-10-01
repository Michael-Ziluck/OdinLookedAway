[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path $root ('.local/deploy-checks/' + [guid]::NewGuid().ToString('N'))
$profile = Join-Path $fixture 'profile'
$saves = Join-Path $fixture 'saves'
New-Item -ItemType Directory -Path (Join-Path $profile 'BepInEx/plugins/OdinLookedAway'), $saves -Force | Out-Null
$target = Join-Path $profile 'BepInEx/plugins/OdinLookedAway/OdinLookedAway.dll'
$save = Join-Path $saves 'disposable.fch'
[IO.File]::WriteAllText($save, 'original test save')
[IO.File]::WriteAllText($target, 'previous test plugin')
# Mock the process check only inside this fixture-only test. No real profile or
# save path is passed to the deployment scripts, even if the game is running.
function Get-Process { [CmdletBinding()] param([string[]]$Name) }
function Assert($Condition, $Message) { if (!$Condition) { throw $Message } }
$backupRoot = Join-Path $root '.local/rollback'
$before = @(Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object FullName)
& (Join-Path $PSScriptRoot 'Deploy.ps1') -ProfilePath $profile -SavePaths $saves -WhatIf
Assert ((Get-Content -LiteralPath $target -Raw) -eq 'previous test plugin') 'WhatIf changed the plugin.'
& (Join-Path $PSScriptRoot 'Deploy.ps1') -ProfilePath $profile -SavePaths $saves
$backup = @(Get-ChildItem -LiteralPath $backupRoot -Directory | Where-Object { $_.FullName -notin $before })
Assert ($backup.Count -eq 1) 'Expected exactly one verified rollback.'
$record = Get-Content -LiteralPath (Join-Path $backup[0].FullName 'plugin.json') -Raw | ConvertFrom-Json
Assert ($record.target -eq $target) 'Rollback unexpectedly points outside the fixture.'
Assert ((Get-FileHash -LiteralPath $target).Hash -eq (Get-FileHash -LiteralPath (Join-Path $root 'bin/Release/net48/OdinLookedAway.dll')).Hash) 'Deployed DLL mismatch.'
[IO.File]::WriteAllText($save, 'changed test save')
& (Join-Path $PSScriptRoot 'Rollback.ps1') -BackupDirectory $backup[0].FullName -RestoreSaves
Assert ((Get-Content -LiteralPath $save -Raw) -eq 'original test save') 'Save rollback failed.'
Assert ((Get-Content -LiteralPath $target -Raw) -eq 'previous test plugin') 'Plugin rollback failed.'
# New-install rollback must remove only the verified deployed DLL.
Remove-Item -LiteralPath $target
$before = @(Get-ChildItem -LiteralPath $backupRoot -Directory | ForEach-Object FullName)
& (Join-Path $PSScriptRoot 'Deploy.ps1') -ProfilePath $profile -SavePaths $saves
$backup = @(Get-ChildItem -LiteralPath $backupRoot -Directory | Where-Object { $_.FullName -notin $before })
Assert ($backup.Count -eq 1) 'New installation did not produce one rollback.'
$record = Get-Content -LiteralPath (Join-Path $backup[0].FullName 'plugin.json') -Raw | ConvertFrom-Json
Assert ($record.target -eq $target) 'Rollback unexpectedly points outside the fixture.'
& (Join-Path $PSScriptRoot 'Rollback.ps1') -BackupDirectory $backup[0].FullName
Assert (!(Test-Path -LiteralPath $target)) 'New-install rollback did not remove the mod.'
Write-Host 'PASS: fixture-only deployment preview, save/plugin backup hashes, replacement rollback, save restoration, and new-install removal.'
