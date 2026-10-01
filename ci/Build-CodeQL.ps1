[CmdletBinding()]
param([Parameter(Mandatory)][string]$GamePath)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$projects = @(Get-ChildItem -LiteralPath $root -Filter '*.csproj' -File)
if ($projects.Count -ne 1) { throw 'Expected one production mod project.' }
# Force compiler execution under the CodeQL tracer. Test projects with simulated
# game classes are verified separately by Build.ps1 and must not substitute for
# the production game's actual assembly references during security analysis.
Push-Location $root
try {
    & dotnet build $projects[0].FullName -c Release -t:Rebuild '-p:UseSharedCompilation=false' "-p:GamePath=$GamePath"
    if ($LASTEXITCODE -ne 0) { throw 'CodeQL production build failed.' }
    $plugin = Join-Path $root "bin/Release/net48/$($projects[0].BaseName).dll"
    & (Join-Path $PSScriptRoot 'Verify-References.ps1') -GamePath $GamePath -PluginPath $plugin
} finally { Pop-Location }
