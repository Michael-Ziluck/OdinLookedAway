[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$BackupDirectory,
    [switch]$RestoreSaves
)

$ErrorActionPreference = 'Stop'
if (Get-Process -Name valheim, valheim_server -ErrorAction SilentlyContinue) {
    throw 'Close Valheim and dedicated servers before rollback.'
}
$backupDirectoryPath = (Resolve-Path -LiteralPath $BackupDirectory).Path
$pluginBackup = Get-Content -LiteralPath (Join-Path $backupDirectoryPath 'plugin.json') -Raw | ConvertFrom-Json
$saveBackup = Get-Content -LiteralPath (Join-Path $backupDirectoryPath 'saves.json') -Raw | ConvertFrom-Json

if ($pluginBackup.existed) {
    if ((Get-FileHash -LiteralPath (Join-Path $backupDirectoryPath 'previous-plugin.dll')).Hash -ne $pluginBackup.oldHash) {
        throw 'Previous plugin backup is damaged.'
    }
}
if (!$pluginBackup.existed -and (Test-Path -LiteralPath $pluginBackup.target)) {
    # A new-install rollback must not delete a DLL installed or changed later.
    if ((Get-FileHash -LiteralPath $pluginBackup.target).Hash -ne $pluginBackup.deployedHash) {
        throw 'Installed DLL changed after deployment; refusing to remove it.'
    }
}
if ($RestoreSaves) {
    # Validate every save backup before restoring anything; reject paths outside it.
    $backupRootPrefix = $backupDirectoryPath.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    foreach ($saveFile in $saveBackup.files) {
        $backupFilePath = [IO.Path]::GetFullPath((Join-Path $backupDirectoryPath $saveFile.backup))
        if (!$backupFilePath.StartsWith($backupRootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Invalid backup path.'
        }
        if ((Get-FileHash -LiteralPath $backupFilePath).Hash -ne $saveFile.sha256) {
            throw "Damaged save backup: $backupFilePath"
        }
    }
}

if ($PSCmdlet.ShouldProcess($pluginBackup.target, 'Restore previous plugin or remove OdinLookedAway')) {
    if ($pluginBackup.existed) {
        Copy-Item -LiteralPath (Join-Path $backupDirectoryPath 'previous-plugin.dll') -Destination $pluginBackup.target -Force
        if ((Get-FileHash -LiteralPath $pluginBackup.target).Hash -ne $pluginBackup.oldHash) {
            throw 'Plugin restore verification failed.'
        }
    }
    elseif (Test-Path -LiteralPath $pluginBackup.target) {
        Remove-Item -LiteralPath $pluginBackup.target
    }
}
if ($RestoreSaves) {
    foreach ($saveFile in $saveBackup.files) {
        if ($PSCmdlet.ShouldProcess($saveFile.original, 'Restore backed-up save file')) {
            New-Item -ItemType Directory -Path (Split-Path $saveFile.original -Parent) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $backupDirectoryPath $saveFile.backup) -Destination $saveFile.original -Force
            if ((Get-FileHash -LiteralPath $saveFile.original).Hash -ne $saveFile.sha256) {
                throw "Save restore verification failed: $($saveFile.original)"
            }
        }
    }
}
