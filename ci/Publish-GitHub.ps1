param(
    [Parameter(Mandatory)][string]$PackageFile
)

$ErrorActionPreference = 'Stop'
# Leave releases disabled while the release README is being reviewed.
throw 'Publication is disabled pending README review.'

. (Join-Path $PSScriptRoot 'Package-Manifest.ps1')
$manifest = Get-PackageManifest $PackageFile
$modProjects = @(Get-ChildItem (Split-Path $PSScriptRoot -Parent) -Filter '*.csproj' -File)
if ($modProjects.Count -ne 1) {
    throw 'Expected one mod project to determine the release name.'
}
$releaseTitle = "$($modProjects[0].BaseName) $($manifest.version_number)"
$releaseTag = "v$($manifest.version_number)"
& gh release view $releaseTag --repo $env:GITHUB_REPOSITORY --json tagName 2>$null
# Keep existing release assets; only normalize the display title.
if ($LASTEXITCODE -eq 0) {
    & gh release edit $releaseTag --repo $env:GITHUB_REPOSITORY --title $releaseTitle
    if ($LASTEXITCODE -ne 0) {
        throw 'GitHub release title update failed.'
    }
    Write-Host "$releaseTag already exists; retaining its assets and updating its title."
    return
}
$changelog = Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) 'CHANGELOG.md') -Raw
$releaseNotes = [regex]::Match($changelog, '(?ms)^## ' + [regex]::Escape($manifest.version_number) + '\s*\r?\n(.*?)(?=^## |\z)').Groups[1].Value.Trim()
if (!$releaseNotes) {
    throw 'Add release notes to CHANGELOG.md before publishing.'
}
$notesPath = Join-Path $env:RUNNER_TEMP 'release-notes.md'
# Pass the notes as a file to preserve newlines and avoid shell quoting surprises.
$releaseNotes | Set-Content $notesPath -Encoding utf8
& gh release create $releaseTag $PackageFile --repo $env:GITHUB_REPOSITORY --target $env:GITHUB_SHA --title $releaseTitle --notes-file $notesPath
if ($LASTEXITCODE -ne 0) {
    throw 'GitHub release creation failed.'
}
