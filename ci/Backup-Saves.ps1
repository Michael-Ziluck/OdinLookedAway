[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$SavePaths,
    [Parameter(Mandatory)][string]$Destination
)

$ErrorActionPreference = 'Stop'

function Assert-NoLinkedAncestor {
    param([string]$Path)

    for ($ancestor = $Path; $ancestor; $ancestor = Split-Path -Path $ancestor -Parent) {
        if (Test-Path -LiteralPath $ancestor) {
            $entry = Get-Item -LiteralPath $ancestor -Force
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Save backups do not support linked paths: $ancestor"
            }
        }
    }
}

if (Get-Process -Name valheim, valheim_server -ErrorAction SilentlyContinue) {
    throw 'Close Valheim and dedicated servers before backing up saves.'
}
$destinationRoot = [IO.Path]::GetFullPath($Destination)
$saveRoots = @($SavePaths | ForEach-Object { (Resolve-Path -LiteralPath $_).Path } | Select-Object -Unique)
$sourceFiles = @{}
Assert-NoLinkedAncestor $destinationRoot

foreach ($saveRoot in $saveRoots) {
    Assert-NoLinkedAncestor $saveRoot
    if (!(Test-Path -LiteralPath $saveRoot -PathType Container)) {
        throw "Expected a save folder: $saveRoot"
    }
    $saveRootPrefix = $saveRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if ($destinationRoot.StartsWith($saveRootPrefix, [StringComparison]::OrdinalIgnoreCase) -or $destinationRoot -eq $saveRoot) {
        throw 'Backup destination must be outside every source save folder.'
    }
    # PowerShell skips linked directories during recursion. Reject them before
    # creating a rollback rather than silently leaving saves out of it.
    $entries = @(Get-ChildItem -LiteralPath $saveRoot -Recurse -Force)
    foreach ($entry in $entries) {
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Save backups do not support linked paths: $($entry.FullName)"
        }
    }
    $sourceFiles[$saveRoot] = @($entries | Where-Object { !$_.PSIsContainer })
}
if (Test-Path -LiteralPath $destinationRoot) {
    throw 'Use a new backup directory; never overwrite a rollback.'
}
New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
$saveFileRecords = @()

# Each source gets its own numbered folder, so identical filenames cannot collide.
for ($index = 0; $index -lt $saveRoots.Count; $index++) {
    $saveRoot = $saveRoots[$index]
    foreach ($file in $sourceFiles[$saveRoot]) {
        $relativePath = [IO.Path]::GetRelativePath($saveRoot, $file.FullName)
        $backupPath = Join-Path $destinationRoot "saves/$index/$relativePath"
        New-Item -ItemType Directory -Path (Split-Path $backupPath -Parent) -Force | Out-Null
        $sourceHash = (Get-FileHash -LiteralPath $file.FullName).Hash
        Copy-Item -LiteralPath $file.FullName -Destination $backupPath
        # Recheck the source too: a file changed during copying is not a safe backup.
        if ((Get-FileHash -LiteralPath $backupPath).Hash -ne $sourceHash -or
            (Get-FileHash -LiteralPath $file.FullName).Hash -ne $sourceHash) {
            throw "Save backup verification failed: $($file.FullName)"
        }
        $saveFileRecords += [ordered]@{
            original = $file.FullName
            backup   = [IO.Path]::GetRelativePath($destinationRoot, $backupPath)
            sha256   = $sourceHash
        }
    }
}
if (!$saveFileRecords.Count) {
    throw 'No save files found; refusing an empty rollback.'
}

[ordered]@{
    version    = 1
    createdUtc = [DateTime]::UtcNow.ToString('o')
    files      = $saveFileRecords
} |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $destinationRoot 'saves.json') -Encoding utf8
Write-Host "Hash-verified $($saveFileRecords.Count) save files: $destinationRoot"
