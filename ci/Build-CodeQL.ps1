[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$GamePath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$modProjects = @(Get-ChildItem -LiteralPath $projectRoot -Filter '*.csproj' -File)
if ($modProjects.Count -ne 1) {
    throw 'Expected one production mod project.'
}
# Rebuild under the CodeQL tracer, using the game's actual assembly references.
# Build.ps1 runs the .NET 8 checks separately; they are not the shipped plugin.

Push-Location $projectRoot
try {
    & dotnet build $modProjects[0].FullName -c Release -t:Rebuild '-p:UseSharedCompilation=false' "-p:GamePath=$GamePath"
    if ($LASTEXITCODE -ne 0) {
        throw 'CodeQL production build failed.'
    }
    $pluginPath = Join-Path $projectRoot "bin/Release/net48/$($modProjects[0].BaseName).dll"
    & (Join-Path $PSScriptRoot 'Verify-References.ps1') -GamePath $GamePath -PluginPath $pluginPath
}
finally {
    Pop-Location
}
