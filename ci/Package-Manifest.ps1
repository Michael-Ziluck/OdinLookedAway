function Get-PackageManifest {
    param([string]$PackageFile)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $packageArchive = [IO.Compression.ZipFile]::OpenRead($PackageFile)
    try {
        foreach ($entryName in @('manifest.json', 'README.md', 'icon.png')) {
            if (!$packageArchive.GetEntry($entryName)) {
                throw "Missing ZIP entry: $entryName"
            }
        }
        if (!($packageArchive.Entries | Where-Object FullName -match '\.dll$')) {
            throw 'No plugin DLL in package.'
        }
        $manifestReader = [IO.StreamReader]::new($packageArchive.GetEntry('manifest.json').Open())
        try {
            $manifest = $manifestReader.ReadToEnd() | ConvertFrom-Json
        }
        finally {
            $manifestReader.Dispose()
        }
    }
    finally {
        $packageArchive.Dispose()
    }
    if ($manifest.name -notmatch '^[A-Za-z0-9_]+$' -or $manifest.version_number -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') {
        throw 'Invalid package name or version.'
    }
    return $manifest
}

function Resolve-Package {
    param(
        [string]$PackageFile,
        [string]$Root
    )

    if (!$PackageFile) {
        $currentManifest = Get-Content (Join-Path $Root 'manifest.json') -Raw | ConvertFrom-Json
        $PackageFile = Join-Path $Root "artifacts/$($currentManifest.name)-$($currentManifest.version_number)-Thunderstore.zip"
    }
    if (!(Test-Path -LiteralPath $PackageFile -PathType Leaf)) {
        throw 'Build a ZIP first or pass -PackageFile.'
    }
    return (Resolve-Path -LiteralPath $PackageFile).Path
}
