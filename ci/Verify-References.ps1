param(
    [Parameter(Mandatory)][string]$GamePath,
    [Parameter(Mandatory)][string]$PluginPath
)

$ErrorActionPreference = 'Stop'
$managedDirectory = Join-Path $GamePath 'valheim_Data/Managed'
$coreDirectory = Join-Path $GamePath 'BepInEx/core'
Add-Type -Path (Join-Path $coreDirectory 'Mono.Cecil.dll')
# Resolve metadata without executing game code or requiring Unity's native runtime.
$resolver = [Mono.Cecil.DefaultAssemblyResolver]::new()
foreach ($directory in @($managedDirectory, $coreDirectory, (Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319'))) {
    $resolver.AddSearchDirectory($directory)
}
$readerParameters = [Mono.Cecil.ReaderParameters]::new()
$readerParameters.AssemblyResolver = $resolver
$pluginModule = [Mono.Cecil.ModuleDefinition]::ReadModule($PluginPath, $readerParameters)
try {
    $checkedReferences = 0
    $unresolvedReferences = @()
    foreach ($member in $pluginModule.GetMemberReferences()) {
        $assemblyScope = $member.DeclaringType.Scope.Name
        # Limit the check to game, Unity, BepInEx, and Harmony references.
        if ($assemblyScope -notmatch '^(assembly_|Unity|BepInEx$|0Harmony$)') {
            continue
        }
        $checkedReferences++
        try {
            if ($null -eq $member.Resolve()) {
                $unresolvedReferences += $member.FullName
            }
        }
        catch {
            $unresolvedReferences += "$($member.FullName): $($_.Exception.Message)"
        }
    }
    if ($unresolvedReferences.Count) {
        throw "Unresolved game/framework references:`n$($unresolvedReferences -join "`n")"
    }
    Write-Host "PASS: $checkedReferences game/framework member references resolve, including bundled libraries."
}
finally {
    $pluginModule.Dispose()
    $resolver.Dispose()
}
