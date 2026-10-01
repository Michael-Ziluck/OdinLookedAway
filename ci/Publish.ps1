[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$PackageFile = '',
    [ValidateSet('Thunderstore', 'Hexium')][string]$Registry = 'Thunderstore',
    [string]$Repository = '',
    [ValidatePattern('^[A-Za-z0-9_]+$')][string]$TeamName = 'DocZee',
    [switch]$SkipExisting
)

$ErrorActionPreference = 'Stop'
# Keep this guard before credential reads or network requests until publication is enabled.
throw 'Publication is disabled for this unpublished project. Obtain explicit publication authorization before changing this guard.'

$projectRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'Package-Manifest.ps1')
$PackageFile = Resolve-Package $PackageFile $projectRoot
$manifest = Get-PackageManifest $PackageFile
$expectedManifest = Get-Content (Join-Path $projectRoot 'manifest.json') -Raw | ConvertFrom-Json
if ($manifest.name -ne $expectedManifest.name) {
    throw 'ZIP belongs to a different mod.'
}
if (!$Repository) {
    $Repository = if ($Registry -eq 'Hexium') {
        'https://valheim.hexium.gg'
    }
    else {
        'https://thunderstore.io'
    }
}
$Repository = $Repository.TrimEnd('/')
$packageId = "$TeamName/$($manifest.name)/$($manifest.version_number)"
if ($SkipExisting) {
    try {
        if ($Registry -eq 'Thunderstore') {
            $null = Invoke-WebRequest "$Repository/package/download/$packageId/" -Method Head -TimeoutSec 30
        }
        else {
            $null = Invoke-RestMethod "$Repository/api/experimental/package/$packageId/" -TimeoutSec 30
        }
        Write-Host "$Registry already has $packageId; skipping immutable version."
        return
    }
    catch {
        if (!$_.Exception.Response -or [int]$_.Exception.Response.StatusCode -ne 404) {
            throw
        }
    }
}
Write-Host "Package: $PackageFile"
Write-Host "Destination: $Registry / $packageId"
if (!$PSCmdlet.ShouldProcess("$Repository/$packageId", 'Publish package')) {
    return
}
$tokenVariableName = if ($Registry -eq 'Hexium') {
    'HEXIUM_API_TOKEN'
}
else {
    'THUNDERSTORE_API_TOKEN'
}
$apiToken = [Environment]::GetEnvironmentVariable($tokenVariableName, 'Process')
if ([string]::IsNullOrWhiteSpace($apiToken)) {
    $apiToken = [Environment]::GetEnvironmentVariable($tokenVariableName, 'User')
}
if ([string]::IsNullOrWhiteSpace($apiToken)) {
    throw "$tokenVariableName is not set."
}

$stagingDirectory = Join-Path $projectRoot ('.local/publish-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stagingDirectory -Force | Out-Null
[IO.Compression.ZipFile]::ExtractToDirectory($PackageFile, $stagingDirectory)
# TCLI's metadata must match the ZIP being uploaded, not a newer working tree.
function ConvertTo-TomlString {
    param([string]$Value)

    return ConvertTo-Json -InputObject ([string]$Value) -Compress
}
$tomlLines = @(
    '[config]'
    'schemaVersion = "0.0.1"'
    '[package]'
    "namespace = $(ConvertTo-TomlString $TeamName)"
    "name = $(ConvertTo-TomlString $manifest.name)"
    "versionNumber = $(ConvertTo-TomlString $manifest.version_number)"
    "description = $(ConvertTo-TomlString $manifest.description)"
    "websiteUrl = $(ConvertTo-TomlString $manifest.website_url)"
    'containsNsfwContent = false'
    '[package.dependencies]'
)
foreach ($dependency in $manifest.dependencies) {
    if ($dependency -notmatch '^([A-Za-z0-9_]+-[A-Za-z0-9_]+)-(\d+\.\d+\.\d+)$') {
        throw "Invalid dependency: $dependency"
    }
    $tomlLines += "$(ConvertTo-TomlString $Matches[1]) = $(ConvertTo-TomlString $Matches[2])"
}
$tomlLines += @(
    '[build]'
    'icon = "./icon.png"'
    'readme = "./README.md"'
    'outdir = "./output"'
    '[[build.copy]]'
    'source = "./BepInEx"'
    'target = "BepInEx"'
    '[publish]'
    "repository = $(ConvertTo-TomlString $Repository)"
    'communities = ["valheim"]'
)
$tomlPath = Join-Path $stagingDirectory 'thunderstore.toml'
$tomlLines | Set-Content -LiteralPath $tomlPath -Encoding utf8

# TCLI needs process-scoped settings; restore them even when publishing fails.
$previousToken = $env:TCLI_AUTH_TOKEN
$previousRollForward = $env:DOTNET_ROLL_FORWARD
Push-Location $projectRoot
try {
    & dotnet tool restore
    if ($LASTEXITCODE -ne 0) {
        throw 'Thunderstore CLI restore failed.'
    }
    $env:TCLI_AUTH_TOKEN = $apiToken
    $env:DOTNET_ROLL_FORWARD = 'Major'
    & dotnet tool run tcli -- publish --file $PackageFile --config-path $tomlPath
    if ($LASTEXITCODE -ne 0) {
        throw "$Registry publish failed with exit code $LASTEXITCODE."
    }
    Write-Host "Published $packageId to $Registry."
}
finally {
    $env:TCLI_AUTH_TOKEN = $previousToken
    $env:DOTNET_ROLL_FORWARD = $previousRollForward
    Pop-Location
}
