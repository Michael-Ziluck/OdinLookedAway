[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$PackageFile = '',
    [ValidateSet('Thunderstore', 'Hexium')][string]$Registry = 'Thunderstore',
    [string]$Repository = '',
    [ValidatePattern('^[A-Za-z0-9_]+$')][string]$TeamName = 'DocZee',
    [switch]$SkipExisting
)
$ErrorActionPreference = 'Stop'
throw 'Publication is disabled for this unpublished project. Obtain explicit publication authorization before changing this guard.'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'Package-Manifest.ps1')
$PackageFile = Resolve-Package $PackageFile $root
$manifest = Get-PackageManifest $PackageFile
$expected = Get-Content (Join-Path $root 'manifest.json') -Raw | ConvertFrom-Json
if ($manifest.name -ne $expected.name) { throw 'ZIP belongs to a different mod.' }
if (!$Repository) {
    $Repository = if ($Registry -eq 'Hexium') { 'https://valheim.hexium.gg' } else { 'https://thunderstore.io' }
}
$Repository = $Repository.TrimEnd('/')
$id = "$TeamName/$($manifest.name)/$($manifest.version_number)"
if ($SkipExisting) {
    try {
        if ($Registry -eq 'Thunderstore') {
            $null = Invoke-WebRequest "$Repository/package/download/$id/" -Method Head -TimeoutSec 30
        } else {
            $null = Invoke-RestMethod "$Repository/api/experimental/package/$id/" -TimeoutSec 30
        }
        Write-Host "$Registry already has $id; skipping immutable version."
        return
    } catch {
        if (!$_.Exception.Response -or [int]$_.Exception.Response.StatusCode -ne 404) { throw }
    }
}
Write-Host "Package: $PackageFile"
Write-Host "Destination: $Registry / $id"
if (!$PSCmdlet.ShouldProcess("$Repository/$id", 'Publish package')) { return }
$tokenName = if ($Registry -eq 'Hexium') { 'HEXIUM_API_TOKEN' } else { 'THUNDERSTORE_API_TOKEN' }
$token = [Environment]::GetEnvironmentVariable($tokenName, 'Process')
if ([string]::IsNullOrWhiteSpace($token)) { $token = [Environment]::GetEnvironmentVariable($tokenName, 'User') }
if ([string]::IsNullOrWhiteSpace($token)) { throw "$tokenName is not set." }

$stage = Join-Path $root ('.local/publish-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
[IO.Compression.ZipFile]::ExtractToDirectory($PackageFile, $stage)
# TCLI reads publication metadata from TOML. Generate it from this exact ZIP,
# keeping future version bumps and dependencies consistent with the upload.
function Toml-String($Value) { return ConvertTo-Json -InputObject ([string]$Value) -Compress }
$config = @(
    '[config]', 'schemaVersion = "0.0.1"', '[package]',
    "namespace = $(Toml-String $TeamName)", "name = $(Toml-String $manifest.name)",
    "versionNumber = $(Toml-String $manifest.version_number)",
    "description = $(Toml-String $manifest.description)", "websiteUrl = $(Toml-String $manifest.website_url)",
    'containsNsfwContent = false', '[package.dependencies]'
)
foreach ($dependency in $manifest.dependencies) {
    if ($dependency -notmatch '^([A-Za-z0-9_]+-[A-Za-z0-9_]+)-(\d+\.\d+\.\d+)$') { throw "Invalid dependency: $dependency" }
    $config += "$(Toml-String $Matches[1]) = $(Toml-String $Matches[2])"
}
$config += @('[build]', 'icon = "./icon.png"', 'readme = "./README.md"', 'outdir = "./output"',
    '[[build.copy]]', 'source = "./BepInEx"', 'target = "BepInEx"',
    '[publish]', "repository = $(Toml-String $Repository)", 'communities = ["valheim"]')
$configPath = Join-Path $stage 'thunderstore.toml'
$config | Set-Content -LiteralPath $configPath -Encoding utf8
$previousToken = $env:TCLI_AUTH_TOKEN
$previousRollForward = $env:DOTNET_ROLL_FORWARD
Push-Location $root
try {
    & dotnet tool restore
    if ($LASTEXITCODE -ne 0) { throw 'Thunderstore CLI restore failed.' }
    $env:TCLI_AUTH_TOKEN = $token
    $env:DOTNET_ROLL_FORWARD = 'Major'
    & dotnet tool run tcli -- publish --file $PackageFile --config-path $configPath
    if ($LASTEXITCODE -ne 0) { throw "$Registry publish failed with exit code $LASTEXITCODE." }
    Write-Host "Published $id to $Registry."
} finally {
    $env:TCLI_AUTH_TOKEN = $previousToken
    $env:DOTNET_ROLL_FORWARD = $previousRollForward
    Pop-Location
}
