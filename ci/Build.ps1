param(
    [string]$GamePath = 'E:\Games\SteamLibrary\steamapps\common\Valheim',
    [string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts')
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$pluginPath = Join-Path $projectRoot 'bin/Release/net48/OdinLookedAway.dll'
$checksAssemblyPath = Join-Path $projectRoot 'tests/checks/bin/Release/net8.0/Checks.dll'

Push-Location $projectRoot
try {
    dotnet build OdinLookedAway.csproj -c Release "-p:GamePath=$GamePath"
    if ($LASTEXITCODE -ne 0) {
        throw 'Release build failed'
    }

    # The mod targets net48; its standalone checks run on .NET 8.
    dotnet build tests/checks/Checks.csproj -c Release "-p:GamePath=$GamePath"
    if ($LASTEXITCODE -ne 0) {
        throw 'Check build failed'
    }

    dotnet $checksAssemblyPath $GamePath $pluginPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Checks failed'
    }

    & (Join-Path $PSScriptRoot 'Verify-References.ps1') -GamePath $GamePath -PluginPath $pluginPath
    & (Join-Path $PSScriptRoot 'Check-Deployment.ps1')
    & (Join-Path $PSScriptRoot 'Package.ps1') -OutputDirectory $OutputDirectory
}
finally {
    Pop-Location
}
