[CmdletBinding()]
param(
    [string]$Destination = (Join-Path (Split-Path $PSScriptRoot -Parent) '.ci-game'),
    [string]$SourceGamePath = ''
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$deps = Get-Content (Join-Path $PSScriptRoot 'dependencies.json') -Raw | ConvertFrom-Json
$Destination = [IO.Path]::GetFullPath($Destination)
$downloads = Join-Path $root '.ci-downloads'
New-Item -ItemType Directory -Path $Destination, $downloads -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-VerifiedArchive($Spec, $FileName) {
    $file = Join-Path $downloads $FileName
    if (!(Test-Path -LiteralPath $file) -or (Get-FileHash -LiteralPath $file).Hash -ne $Spec.sha256) {
        Invoke-WebRequest -Uri $Spec.url -OutFile $file
    }
    if ((Get-FileHash -LiteralPath $file).Hash -ne $Spec.sha256) { throw "Download checksum mismatch: $FileName" }
    return $file
}

$core = Join-Path $Destination 'BepInEx/core'
if (!(Test-Path -LiteralPath (Join-Path $core 'BepInEx.dll'))) {
    $pack = Get-VerifiedArchive $deps.bepinex 'bepinex.zip'
    $unpacked = Join-Path $downloads 'bepinex'
    Expand-Archive -LiteralPath $pack -DestinationPath $unpacked -Force
    New-Item -ItemType Directory -Path $core -Force | Out-Null
    Get-ChildItem (Join-Path $unpacked 'BepInExPack_Valheim/BepInEx/core') -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $core -Force
    }
}
$managed = Join-Path $Destination 'valheim_Data/Managed'
if (!(Test-Path -LiteralPath (Join-Path $managed 'assembly_valheim.dll'))) {
    if ($SourceGamePath) {
        $sourceManaged = Join-Path $SourceGamePath 'valheim_Data/Managed'
    } else {
        $steamArchive = Get-VerifiedArchive $deps.steamcmd 'steamcmd.zip'
        $steamDir = Join-Path $downloads 'steamcmd'
        Expand-Archive -LiteralPath $steamArchive -DestinationPath $steamDir -Force
        $serverDir = Join-Path $downloads 'server'
        # Fresh SteamCMD installations can have incomplete app metadata. Refresh it
        # explicitly, select the public branch, and allow bounded download retries.
        Push-Location $steamDir
        try {
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                & (Join-Path $steamDir 'steamcmd.exe') +force_install_dir $serverDir +login anonymous +app_info_update 1 +app_update $deps.steamcmd.serverAppId -beta public validate +quit
                if ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $serverDir 'valheim_server_Data/Managed/assembly_valheim.dll'))) { break }
                if ($attempt -eq 3) { throw "SteamCMD failed after $attempt attempts (exit $LASTEXITCODE)." }
                Write-Host "SteamCMD download incomplete; retrying ($attempt/3)."
                Start-Sleep -Seconds 5
            }
        } finally { Pop-Location }
        $sourceManaged = Join-Path $serverDir 'valheim_server_Data/Managed'
    }
    if (!(Test-Path -LiteralPath (Join-Path $sourceManaged 'assembly_valheim.dll'))) { throw 'Valheim game assemblies were not obtained.' }
    New-Item -ItemType Directory -Path $managed -Force | Out-Null
    Get-ChildItem -LiteralPath $sourceManaged -Filter '*.dll' -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $managed -Force
    }
}

# Inspect metadata only; never start the game or load Unity native code.
Add-Type -Path (Join-Path $core 'Mono.Cecil.dll')
$module = [Mono.Cecil.ModuleDefinition]::ReadModule((Join-Path $managed 'assembly_valheim.dll'))
try {
    $type = $module.Types | Where-Object Name -eq 'Version'
    $initializer = $type.Methods | Where-Object Name -eq '.cctor'
    $assignment = $initializer.Body.Instructions | Where-Object {
        $_.OpCode.Name -eq 'stsfld' -and $_.Operand.Name -eq '<CurrentVersion>k__BackingField'
    } | Select-Object -First 1
    if (!$assignment) { throw 'Cannot determine Valheim version from game assembly.' }
    function Read-Int($Instruction) {
        if ($Instruction.OpCode.Name -in @('ldc.i4', 'ldc.i4.s')) { return [int]$Instruction.Operand }
        if ($Instruction.OpCode.Name -match '^ldc\.i4\.([0-8])$') { return [int]$Matches[1] }
        throw 'Unrecognized game version constructor.'
    }
    $patch = Read-Int $assignment.Previous.Previous
    $minor = Read-Int $assignment.Previous.Previous.Previous
    $major = Read-Int $assignment.Previous.Previous.Previous.Previous
    if ($major -ne $deps.gameMajorVersion) { throw "Expected Valheim $($deps.gameMajorVersion).x, obtained $major.$minor.$patch" }
    $version = "$major.$minor.$patch"
} finally { $module.Dispose() }
[ordered]@{
    gameVersion = $version
    assemblySha256 = (Get-FileHash (Join-Path $managed 'assembly_valheim.dll')).Hash
    bepinexPack = $deps.bepinex.version
} | ConvertTo-Json | Set-Content (Join-Path $Destination 'build-references.json') -Encoding utf8
Write-Host "Build references ready: Valheim $version, BepInExPack $($deps.bepinex.version)"
if ($env:GITHUB_ENV) { "VALHEIM_BUILD_PATH=$Destination" | Out-File $env:GITHUB_ENV -Append -Encoding utf8 }
