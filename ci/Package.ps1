param(
    [string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts')
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$utf8Encoding = [Text.UTF8Encoding]::new($false, $true)
$manifest = $utf8Encoding.GetString([IO.File]::ReadAllBytes((Join-Path $projectRoot 'manifest.json'))) | ConvertFrom-Json
if ($manifest.name -notmatch '^[A-Za-z0-9_]{1,128}$') {
    throw 'Invalid package name'
}
if ($manifest.version_number -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') {
    throw 'Invalid package version'
}
if (!$manifest.description -or $manifest.description.Length -gt 250) {
    throw 'Invalid description'
}
if ($null -eq $manifest.website_url) {
    throw 'website_url must be present, even when blank'
}
foreach ($dependency in $manifest.dependencies) {
    if ($dependency -notmatch '^[A-Za-z0-9_]+-[A-Za-z0-9_]+-\d+\.\d+\.\d+$') {
        throw "Invalid dependency: $dependency"
    }
}

$assemblyName = (Get-ChildItem -LiteralPath $projectRoot -Filter '*.csproj' | Select-Object -First 1).BaseName
$pluginPath = Join-Path $projectRoot "bin/Release/net48/$assemblyName.dll"
if (!(Test-Path -LiteralPath $pluginPath)) {
    throw 'Build Release before packaging'
}
$assemblyVersion = [Reflection.AssemblyName]::GetAssemblyName($pluginPath).Version.ToString(3)
# Refuse a stale DLL or a version bump made in only one place.
if ($assemblyVersion -ne $manifest.version_number) {
    throw 'Release DLL version does not match manifest.json; rebuild before packaging.'
}
$pluginSource = Get-Content -LiteralPath (Join-Path $projectRoot 'src/Plugin.cs') -Raw
$pluginVersion = [regex]::Match($pluginSource, '\[BepInPlugin\(Guid,\s*"[^"]+",\s*"([^"]+)"\)\]').Groups[1].Value
if ($pluginVersion -ne $manifest.version_number) {
    throw 'Plugin version does not match manifest.json.'
}
$iconBytes = [IO.File]::ReadAllBytes((Join-Path $projectRoot 'icon.png'))
# PNG's IHDR stores width and height as big-endian integers at bytes 16-23.
if ([BitConverter]::ToString($iconBytes[0..7]) -ne '89-50-4E-47-0D-0A-1A-0A') {
    throw 'Icon is not PNG'
}
if ([BitConverter]::ToString($iconBytes[16..23]) -ne '00-00-01-00-00-00-01-00') {
    throw 'Icon must be 256x256'
}
$stagingDirectory = Join-Path $OutputDirectory ('package-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $stagingDirectory "BepInEx/plugins/$assemblyName") -Force | Out-Null
Copy-Item -LiteralPath $pluginPath -Destination (Join-Path $stagingDirectory "BepInEx/plugins/$assemblyName/$assemblyName.dll")
$packageFiles = @('manifest.json', 'icon.png', 'README.md', 'CHANGELOG.md', 'LICENSE', 'ATTRIBUTION.md')
if (Test-Path (Join-Path $projectRoot 'THIRD_PARTY_NOTICES.md')) {
    $packageFiles += 'THIRD_PARTY_NOTICES.md'
}
foreach ($fileName in $packageFiles) {
    # Thunderstore gets the mod-page README; the repository keeps developer docs.
    $sourceFileName = if ($fileName -eq 'README.md') {
        'README.thunderstore.md'
    }
    else {
        $fileName
    }
    if ($fileName -ne 'icon.png') {
        $null = $utf8Encoding.GetString([IO.File]::ReadAllBytes((Join-Path $projectRoot $sourceFileName)))
    }
    Copy-Item -LiteralPath (Join-Path $projectRoot $sourceFileName) -Destination (Join-Path $stagingDirectory $fileName)
}

Add-Type -AssemblyName System.IO.Compression.FileSystem

$zipPath = Join-Path $OutputDirectory ("$($manifest.name)-$($manifest.version_number)-Thunderstore.zip")
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath
}
[IO.Compression.ZipFile]::CreateFromDirectory($stagingDirectory, $zipPath)
$packageArchive = [IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    foreach ($requiredEntry in @('icon.png', 'manifest.json', 'README.md', "BepInEx/plugins/$assemblyName/$assemblyName.dll")) {
        if (!$packageArchive.GetEntry($requiredEntry)) {
            throw "Missing ZIP entry: $requiredEntry"
        }
    }
    if ((Get-Item -LiteralPath $zipPath).Length -gt 5242880000) {
        throw 'Package exceeds Thunderstore size limit'
    }
    $packageArchive.Entries | Select-Object FullName, Length
}
finally {
    $packageArchive.Dispose()
}
Write-Output "Validated package: $zipPath"
