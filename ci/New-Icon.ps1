param(
    [string]$SourcePath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'assets/icon-source.png')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectRoot = Split-Path $PSScriptRoot -Parent
$sourceImage = [Drawing.Image]::FromFile((Resolve-Path -LiteralPath $SourcePath).Path)

try {
    if ($sourceImage.Width -ne $sourceImage.Height) {
        throw 'Use a square source image to avoid stretching the icon.'
    }

    # Keep the supplied artwork intact; only resize for Thunderstore's 256px icon.
    $bitmap = [Drawing.Bitmap]::new(256, 256)
    try {
        $canvas = [Drawing.Graphics]::FromImage($bitmap)
        try {
            $canvas.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
            $canvas.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $canvas.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $canvas.DrawImage($sourceImage, [Drawing.Rectangle]::new(0, 0, 256, 256))
        }
        finally {
            $canvas.Dispose()
        }

        $iconPath = Join-Path $projectRoot 'icon.png'
        $bitmap.Save($iconPath, [Drawing.Imaging.ImageFormat]::Png)
        Write-Host "Icon ready: $iconPath"
    }
    finally {
        $bitmap.Dispose()
    }
}
finally {
    $sourceImage.Dispose()
}
