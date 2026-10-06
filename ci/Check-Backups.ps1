[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$fixtureDirectory = Join-Path $projectRoot ('.local/backup-checks/' + [guid]::NewGuid().ToString('N'))
$saveDirectory = Join-Path $fixtureDirectory 'saves'
$nestedDirectory = Join-Path $saveDirectory 'nested'
New-Item -ItemType Directory -Path $nestedDirectory -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $saveDirectory 'character.fch'), 'character save')
[IO.File]::WriteAllText((Join-Path $nestedDirectory 'world.db'), 'world save')
$hiddenPath = Join-Path $saveDirectory 'hidden.fch'
[IO.File]::WriteAllText($hiddenPath, 'hidden save')
(Get-Item -LiteralPath $hiddenPath).Attributes = [IO.FileAttributes]::Hidden
$backupScript = Join-Path $PSScriptRoot 'Backup-Saves.ps1'

# Only disposable fixture paths reach the backup script.
function Get-Process {
    [CmdletBinding()]
    param([string[]]$Name)
}

function Assert-RejectedBackup {
    param([string[]]$Sources, [string]$Destination, [string]$ExpectedMessage)

    $failure = $null
    try {
        & $backupScript -SavePaths $Sources -Destination $Destination
    } catch {
        $failure = $_.Exception.Message
    }
    if (!$failure -or $failure -notlike $ExpectedMessage) {
        throw "Expected '$ExpectedMessage'; received '$failure'."
    }
    if (Test-Path -LiteralPath $Destination) {
        throw "Rejected backup created a destination: $Destination"
    }
}

$backupDirectory = Join-Path $fixtureDirectory 'verified'
& $backupScript -SavePaths $saveDirectory -Destination $backupDirectory
$manifest = Get-Content -LiteralPath (Join-Path $backupDirectory 'saves.json') -Raw | ConvertFrom-Json
if ($manifest.files.Count -ne 3) {
    throw 'Backup omitted an ordinary, nested, or hidden save.'
}
foreach ($record in $manifest.files) {
    $copiedPath = Join-Path $backupDirectory $record.backup
    if ((Get-FileHash -LiteralPath $copiedPath).Hash -ne $record.sha256 -or
        (Get-FileHash -LiteralPath $record.original).Hash -ne $record.sha256) {
        throw "Fixture backup hash mismatch: $copiedPath"
    }
}
Assert-RejectedBackup $saveDirectory (Join-Path $saveDirectory 'backup') '*outside every source*'

# Junctions require no elevation on Windows and reproduce skipped descendants.
$linkedDirectory = Join-Path $fixtureDirectory 'linked-saves'
New-Item -ItemType Directory -Path $linkedDirectory | Out-Null
[IO.File]::WriteAllText((Join-Path $linkedDirectory 'linked.fch'), 'linked save')
$junctionPath = Join-Path $saveDirectory 'junction'
New-Item -ItemType Junction -Path $junctionPath -Target $linkedDirectory | Out-Null
Assert-RejectedBackup $saveDirectory (Join-Path $fixtureDirectory 'rejected-descendant') '*do not support linked paths*'
Assert-RejectedBackup $junctionPath (Join-Path $fixtureDirectory 'rejected-root') '*do not support linked paths*'
$linkedChild = Join-Path $linkedDirectory 'child'
New-Item -ItemType Directory -Path $linkedChild | Out-Null
Assert-RejectedBackup (Join-Path $junctionPath 'child') (Join-Path $fixtureDirectory 'rejected-ancestor') '*do not support linked paths*'
Assert-RejectedBackup $linkedDirectory (Join-Path $junctionPath 'backup') '*do not support linked paths*'

$ordinaryDirectory = Join-Path $fixtureDirectory 'ordinary'
New-Item -ItemType Directory -Path $ordinaryDirectory | Out-Null
[IO.File]::WriteAllText((Join-Path $ordinaryDirectory 'ordinary.fch'), 'ordinary save')
Assert-RejectedBackup @($ordinaryDirectory, $saveDirectory) (Join-Path $fixtureDirectory 'rejected-second-source') '*do not support linked paths*'
Write-Host 'PASS: ordinary, nested, and hidden save hashes; linked descendants, roots, ancestors, destinations, and multiple-source rejection before copying.'
