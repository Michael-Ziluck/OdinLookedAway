[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$BackupDirectory, [switch]$RestoreSaves)
$ErrorActionPreference = 'Stop'
if (Get-Process -Name valheim,valheim_server -ErrorAction SilentlyContinue) { throw 'Close Valheim and dedicated servers before rollback.' }
$backup = (Resolve-Path -LiteralPath $BackupDirectory).Path
$plugin = Get-Content -LiteralPath (Join-Path $backup 'plugin.json') -Raw | ConvertFrom-Json
$saves = Get-Content -LiteralPath (Join-Path $backup 'saves.json') -Raw | ConvertFrom-Json
if ($plugin.existed) {
    if ((Get-FileHash -LiteralPath (Join-Path $backup 'previous-plugin.dll')).Hash -ne $plugin.oldHash) { throw 'Previous plugin backup is damaged.' }
}
if (!$plugin.existed -and (Test-Path -LiteralPath $plugin.target)) {
    if ((Get-FileHash -LiteralPath $plugin.target).Hash -ne $plugin.deployedHash) { throw 'Installed DLL changed after deployment; refusing to remove it.' }
}
if ($RestoreSaves) {
    foreach ($file in $saves.files) {
        $path = [IO.Path]::GetFullPath((Join-Path $backup $file.backup))
        if (!$path.StartsWith($backup.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid backup path.' }
        if ((Get-FileHash -LiteralPath $path).Hash -ne $file.sha256) { throw "Damaged save backup: $path" }
    }
}
if ($PSCmdlet.ShouldProcess($plugin.target, 'Restore previous plugin or remove OdinLookedAway')) {
    if ($plugin.existed) {
        Copy-Item -LiteralPath (Join-Path $backup 'previous-plugin.dll') -Destination $plugin.target -Force
        if ((Get-FileHash -LiteralPath $plugin.target).Hash -ne $plugin.oldHash) { throw 'Plugin restore verification failed.' }
    } elseif (Test-Path -LiteralPath $plugin.target) { Remove-Item -LiteralPath $plugin.target }
}
if ($RestoreSaves) {
    foreach ($file in $saves.files) {
        if ($PSCmdlet.ShouldProcess($file.original, 'Restore backed-up save file')) {
            New-Item -ItemType Directory -Path (Split-Path $file.original -Parent) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $backup $file.backup) -Destination $file.original -Force
            if ((Get-FileHash -LiteralPath $file.original).Hash -ne $file.sha256) { throw "Save restore verification failed: $($file.original)" }
        }
    }
}
