param([Parameter(Mandatory)][string]$GamePath, [Parameter(Mandatory)][string]$PluginPath)
$ErrorActionPreference = 'Stop'
$managed = Join-Path $GamePath 'valheim_Data/Managed'
$core = Join-Path $GamePath 'BepInEx/core'
Add-Type -Path (Join-Path $core 'Mono.Cecil.dll')
$resolver = [Mono.Cecil.DefaultAssemblyResolver]::new()
foreach ($directory in @($managed, $core, (Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319'))) {
    $resolver.AddSearchDirectory($directory)
}
$parameters = [Mono.Cecil.ReaderParameters]::new()
$parameters.AssemblyResolver = $resolver
$module = [Mono.Cecil.ModuleDefinition]::ReadModule($PluginPath, $parameters)
try {
    $checked = 0
    $missing = @()
    foreach ($member in $module.GetMemberReferences()) {
        $scope = $member.DeclaringType.Scope.Name
        if ($scope -notmatch '^(assembly_|Unity|BepInEx$|0Harmony$)') { continue }
        $checked++
        try {
            if ($null -eq $member.Resolve()) { $missing += $member.FullName }
        } catch { $missing += "$($member.FullName): $($_.Exception.Message)" }
    }
    if ($missing.Count) { throw "Unresolved game/framework references:`n$($missing -join "`n")" }
    Write-Host "PASS: $checked game/framework member references resolve, including bundled libraries."
} finally { $module.Dispose(); $resolver.Dispose() }
