[CmdletBinding()]
param(
    [string]$Destination = (Join-Path (Split-Path $PSScriptRoot -Parent) '.ci-game'),
    [string]$SourceGamePath = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$dependencies = Get-Content (Join-Path $PSScriptRoot 'dependencies.json') -Raw | ConvertFrom-Json
$Destination = [IO.Path]::GetFullPath($Destination)
$downloadDirectory = Join-Path $projectRoot '.ci-downloads'
New-Item -ItemType Directory -Path $Destination, $downloadDirectory -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-VerifiedArchive {
    param($Spec, [string]$FileName)

    $archivePath = Join-Path $downloadDirectory $FileName
    # Cached archives are checked too; filenames alone do not identify a release.
    if (!(Test-Path -LiteralPath $archivePath) -or (Get-FileHash -LiteralPath $archivePath).Hash -ne $Spec.sha256) {
        Invoke-WebRequest -Uri $Spec.url -OutFile $archivePath
    }
    if ((Get-FileHash -LiteralPath $archivePath).Hash -ne $Spec.sha256) {
        throw "Download checksum mismatch: $FileName"
    }
    return $archivePath
}

$coreDirectory = Join-Path $Destination 'BepInEx/core'
if (!(Test-Path -LiteralPath (Join-Path $coreDirectory 'BepInEx.dll'))) {
    $bepinexArchive = Get-VerifiedArchive $dependencies.bepinex 'bepinex.zip'
    $bepinexDirectory = Join-Path $downloadDirectory 'bepinex'
    Expand-Archive -LiteralPath $bepinexArchive -DestinationPath $bepinexDirectory -Force
    New-Item -ItemType Directory -Path $coreDirectory -Force | Out-Null
    Get-ChildItem (Join-Path $bepinexDirectory 'BepInExPack_Valheim/BepInEx/core') -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $coreDirectory -Force
    }
}
$managedDirectory = Join-Path $Destination 'valheim_Data/Managed'
if (!(Test-Path -LiteralPath (Join-Path $managedDirectory 'assembly_valheim.dll'))) {
    if ($SourceGamePath) {
        $sourceManagedDirectory = Join-Path $SourceGamePath 'valheim_Data/Managed'
    }
    else {
        $steamArchive = Get-VerifiedArchive $dependencies.steamcmd 'steamcmd.zip'
        $steamcmdDirectory = Join-Path $downloadDirectory 'steamcmd'
        Expand-Archive -LiteralPath $steamArchive -DestinationPath $steamcmdDirectory -Force
        $serverDirectory = Join-Path $downloadDirectory 'server'
        # A fresh SteamCMD cache may lack app metadata. Refresh it before downloading.
        $steamcmdArguments = @(
            '+force_install_dir', $serverDirectory
            '+login', 'anonymous'
            '+app_info_update', '1'
            '+app_update', $dependencies.steamcmd.serverAppId, '-beta', 'public', 'validate'
            '+quit'
        )
        Push-Location $steamcmdDirectory
        try {
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                & (Join-Path $steamcmdDirectory 'steamcmd.exe') @steamcmdArguments
                if ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $serverDirectory 'valheim_server_Data/Managed/assembly_valheim.dll'))) {
                    break
                }
                if ($attempt -eq 3) {
                    throw "SteamCMD failed after $attempt attempts (exit $LASTEXITCODE)."
                }
                Write-Host "SteamCMD download incomplete; retrying ($attempt/3)."
                Start-Sleep -Seconds 5
            }
        }
        finally {
            Pop-Location
        }
        $sourceManagedDirectory = Join-Path $serverDirectory 'valheim_server_Data/Managed'
    }
    if (!(Test-Path -LiteralPath (Join-Path $sourceManagedDirectory 'assembly_valheim.dll'))) {
        throw 'Valheim game assemblies were not obtained.'
    }
    New-Item -ItemType Directory -Path $managedDirectory -Force | Out-Null
    Get-ChildItem -LiteralPath $sourceManagedDirectory -Filter '*.dll' -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $managedDirectory -Force
    }
}

# Inspect metadata only; never start the game or load Unity native code.
Add-Type -Path (Join-Path $coreDirectory 'Mono.Cecil.dll')
$gameModule = [Mono.Cecil.ModuleDefinition]::ReadModule((Join-Path $managedDirectory 'assembly_valheim.dll'))
try {
    $versionType = $gameModule.Types | Where-Object Name -eq 'Version'
    $versionInitializer = $versionType.Methods | Where-Object Name -eq '.cctor'
    $versionAssignment = $versionInitializer.Body.Instructions | Where-Object {
        $_.OpCode.Name -eq 'stsfld' -and $_.Operand.Name -eq '<CurrentVersion>k__BackingField'
    } | Select-Object -First 1
    if (!$versionAssignment) {
        throw 'Cannot determine Valheim version from game assembly.'
    }
    function Get-IntegerConstant {
        param($Instruction)

        if ($Instruction.OpCode.Name -in @('ldc.i4', 'ldc.i4.s')) {
            return [int]$Instruction.Operand
        }
        if ($Instruction.OpCode.Name -match '^ldc\.i4\.([0-8])$') {
            return [int]$Matches[1]
        }
        throw 'Unrecognized game version constructor.'
    }
    # Skip newobj immediately before the assignment to read the constructor's arguments.
    $patchVersion = Get-IntegerConstant $versionAssignment.Previous.Previous
    $minorVersion = Get-IntegerConstant $versionAssignment.Previous.Previous.Previous
    $majorVersion = Get-IntegerConstant $versionAssignment.Previous.Previous.Previous.Previous
    if ($majorVersion -ne $dependencies.gameMajorVersion) {
        throw "Expected Valheim $($dependencies.gameMajorVersion).x, obtained $majorVersion.$minorVersion.$patchVersion"
    }
    $gameVersion = "$majorVersion.$minorVersion.$patchVersion"
}
finally {
    $gameModule.Dispose()
}

[ordered]@{
    gameVersion    = $gameVersion
    assemblySha256 = (Get-FileHash (Join-Path $managedDirectory 'assembly_valheim.dll')).Hash
    bepinexPack    = $dependencies.bepinex.version
} | ConvertTo-Json | Set-Content (Join-Path $Destination 'build-references.json') -Encoding utf8
Write-Host "Build references ready: Valheim $gameVersion, BepInExPack $($dependencies.bepinex.version)"
if ($env:GITHUB_ENV) {
    "VALHEIM_BUILD_PATH=$Destination" | Out-File $env:GITHUB_ENV -Append -Encoding utf8
}
