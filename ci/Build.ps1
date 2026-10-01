param(
    [string]$GamePath = 'E:\Games\SteamLibrary\steamapps\common\Valheim',
    [string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts')
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    dotnet build OdinLookedAway.csproj -c Release "-p:GamePath=$GamePath"
    if ($LASTEXITCODE -ne 0) { throw 'Release build failed' }
    dotnet build tests/checks/Checks.csproj -c Release "-p:GamePath=$GamePath"
    if ($LASTEXITCODE -ne 0) { throw 'Check build failed' }
    dotnet (Join-Path $root 'tests/checks/bin/Release/net8.0/Checks.dll') $GamePath (Join-Path $root 'bin/Release/net48/OdinLookedAway.dll')
    if ($LASTEXITCODE -ne 0) { throw 'Checks failed' }
    & (Join-Path $PSScriptRoot 'Verify-References.ps1') -GamePath $GamePath -PluginPath (Join-Path $root 'bin/Release/net48/OdinLookedAway.dll')
    & (Join-Path $PSScriptRoot 'Check-Deployment.ps1')
    & (Join-Path $PSScriptRoot 'Package.ps1') -OutputDirectory $OutputDirectory
} finally { Pop-Location }
