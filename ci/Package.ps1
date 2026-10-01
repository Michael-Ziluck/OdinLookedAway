param([string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts'))
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$manifest = $utf8.GetString([IO.File]::ReadAllBytes((Join-Path $root 'manifest.json'))) | ConvertFrom-Json
if ($manifest.name -notmatch '^[A-Za-z0-9_]{1,128}$') { throw 'Invalid package name' }
if ($manifest.version_number -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') { throw 'Invalid package version' }
if (!$manifest.description -or $manifest.description.Length -gt 250) { throw 'Invalid description' }
if ($null -eq $manifest.website_url) { throw 'website_url must be present, even when blank' }
foreach ($dependency in $manifest.dependencies) {
    if ($dependency -notmatch '^[A-Za-z0-9_]+-[A-Za-z0-9_]+-\d+\.\d+\.\d+$') { throw "Invalid dependency: $dependency" }
}
$assemblyName = (Get-ChildItem -LiteralPath $root -Filter '*.csproj' | Select-Object -First 1).BaseName
$dll = Join-Path $root "bin/Release/net48/$assemblyName.dll"
if (!(Test-Path -LiteralPath $dll)) { throw 'Build Release before packaging' }
$assemblyVersion = [Reflection.AssemblyName]::GetAssemblyName($dll).Version.ToString(3)
if ($assemblyVersion -ne $manifest.version_number) { throw 'Release DLL version does not match manifest.json; rebuild before packaging.' }
$pluginSource = Get-Content -LiteralPath (Join-Path $root 'src/Plugin.cs') -Raw
$pluginVersion = [regex]::Match($pluginSource, '\[BepInPlugin\(Guid,\s*"[^"]+",\s*"([^"]+)"\)\]').Groups[1].Value
if ($pluginVersion -ne $manifest.version_number) { throw 'Plugin version does not match manifest.json.' }
$icon = [IO.File]::ReadAllBytes((Join-Path $root 'icon.png'))
if ([BitConverter]::ToString($icon[0..7]) -ne '89-50-4E-47-0D-0A-1A-0A') { throw 'Icon is not PNG' }
if ([BitConverter]::ToString($icon[16..23]) -ne '00-00-01-00-00-00-01-00') { throw 'Icon must be 256x256' }
$stage = Join-Path $OutputDirectory ('package-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $stage "BepInEx/plugins/$assemblyName") -Force | Out-Null
Copy-Item -LiteralPath $dll -Destination (Join-Path $stage "BepInEx/plugins/$assemblyName/$assemblyName.dll")
$packageFiles = @('manifest.json', 'icon.png', 'README.md', 'CHANGELOG.md', 'LICENSE', 'ATTRIBUTION.md')
if (Test-Path (Join-Path $root 'THIRD_PARTY_NOTICES.md')) { $packageFiles += 'THIRD_PARTY_NOTICES.md' }
foreach ($name in $packageFiles) {
    $sourceName = if ($name -eq 'README.md') { 'README.thunderstore.md' } else { $name }
    if ($name -ne 'icon.png') { $null = $utf8.GetString([IO.File]::ReadAllBytes((Join-Path $root $sourceName))) }
    Copy-Item -LiteralPath (Join-Path $root $sourceName) -Destination (Join-Path $stage $name)
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipPath = Join-Path $OutputDirectory ("$($manifest.name)-$($manifest.version_number)-Thunderstore.zip")
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath }
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $zipPath)
$zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    foreach ($required in @('icon.png', 'manifest.json', 'README.md', "BepInEx/plugins/$assemblyName/$assemblyName.dll")) {
        if (!$zip.GetEntry($required)) { throw "Missing ZIP entry: $required" }
    }
    if ((Get-Item -LiteralPath $zipPath).Length -gt 5242880000) { throw 'Package exceeds Thunderstore size limit' }
    $zip.Entries | Select-Object FullName, Length
} finally { $zip.Dispose() }
Write-Output "Validated package: $zipPath"
