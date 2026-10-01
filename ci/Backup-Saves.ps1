[CmdletBinding()]
param([Parameter(Mandatory)][string[]]$SavePaths, [Parameter(Mandatory)][string]$Destination)
$ErrorActionPreference = 'Stop'
if (Get-Process -Name valheim,valheim_server -ErrorAction SilentlyContinue) { throw 'Close Valheim and dedicated servers before backing up saves.' }
$destinationRoot = [IO.Path]::GetFullPath($Destination)
$sources = @($SavePaths | ForEach-Object { (Resolve-Path -LiteralPath $_).Path } | Select-Object -Unique)
foreach ($source in $sources) {
    if (!(Test-Path -LiteralPath $source -PathType Container)) { throw "Expected a save folder: $source" }
    if ($destinationRoot.StartsWith($source.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or $destinationRoot -eq $source) {
        throw 'Backup destination must be outside every source save folder.'
    }
}
if (Test-Path -LiteralPath $destinationRoot) { throw 'Use a new backup directory; never overwrite a rollback.' }
New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
$files = @()
for ($index = 0; $index -lt $sources.Count; $index++) {
    $source = $sources[$index]
    foreach ($file in Get-ChildItem -LiteralPath $source -File -Recurse) {
        $relative = [IO.Path]::GetRelativePath($source, $file.FullName)
        $backupPath = Join-Path $destinationRoot "saves/$index/$relative"
        New-Item -ItemType Directory -Path (Split-Path $backupPath -Parent) -Force | Out-Null
        $before = (Get-FileHash -LiteralPath $file.FullName).Hash
        Copy-Item -LiteralPath $file.FullName -Destination $backupPath
        if ((Get-FileHash -LiteralPath $backupPath).Hash -ne $before -or (Get-FileHash -LiteralPath $file.FullName).Hash -ne $before) { throw "Save backup verification failed: $($file.FullName)" }
        $files += [ordered]@{ original = $file.FullName; backup = [IO.Path]::GetRelativePath($destinationRoot, $backupPath); sha256 = $before }
    }
}
if (!$files.Count) { throw 'No save files found; refusing an empty rollback.' }
[ordered]@{ version = 1; createdUtc = [DateTime]::UtcNow.ToString('o'); files = $files } |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $destinationRoot 'saves.json') -Encoding utf8
Write-Host "Hash-verified $($files.Count) save files: $destinationRoot"
