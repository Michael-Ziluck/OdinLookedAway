param([Parameter(Mandatory)][string]$PackageFile)
$ErrorActionPreference = 'Stop'
throw 'Publication is disabled for this unpublished project. Obtain explicit publication authorization before changing this guard.'
. (Join-Path $PSScriptRoot 'Package-Manifest.ps1')
$manifest = Get-PackageManifest $PackageFile
$project = @(Get-ChildItem (Split-Path $PSScriptRoot -Parent) -Filter '*.csproj' -File)
if ($project.Count -ne 1) { throw 'Expected one mod project to determine the release name.' }
$title = "$($project[0].BaseName) $($manifest.version_number)"
$tag = "v$($manifest.version_number)"
& gh release view $tag --repo $env:GITHUB_REPOSITORY --json tagName 2>$null
if ($LASTEXITCODE -eq 0) {
    & gh release edit $tag --repo $env:GITHUB_REPOSITORY --title $title
    if ($LASTEXITCODE -ne 0) { throw 'GitHub release title update failed.' }
    Write-Host "$tag already exists; retaining its assets and updating its title."
    return
}
$changelog = Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) 'CHANGELOG.md') -Raw
$notes = [regex]::Match($changelog, '(?ms)^## ' + [regex]::Escape($manifest.version_number) + '\s*\r?\n(.*?)(?=^## |\z)').Groups[1].Value.Trim()
if (!$notes) { throw 'Add release notes to CHANGELOG.md before publishing.' }
$notesPath = Join-Path $env:RUNNER_TEMP 'release-notes.md'
$notes | Set-Content $notesPath -Encoding utf8
& gh release create $tag $PackageFile --repo $env:GITHUB_REPOSITORY --target $env:GITHUB_SHA --title $title --notes-file $notesPath
if ($LASTEXITCODE -ne 0) { throw 'GitHub release creation failed.' }
