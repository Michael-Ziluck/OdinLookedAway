param()
$ErrorActionPreference = 'Stop'
# Original geometric artwork; no game art or external image dependencies.
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$bitmap = [Drawing.Bitmap]::new(256, 256)
$graphics = [Drawing.Graphics]::FromImage($bitmap)
$pen = [Drawing.Pen]::new([Drawing.Color]::FromArgb(236, 191, 94), 10)
$pen.StartCap = [Drawing.Drawing2D.LineCap]::Round
$pen.EndCap = [Drawing.Drawing2D.LineCap]::Round
$muted = [Drawing.Pen]::new([Drawing.Color]::FromArgb(158, 118, 60), 6)
try {
    $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([Drawing.Color]::FromArgb(22, 31, 42))
    $graphics.DrawEllipse($muted, 14, 14, 228, 228)
    $graphics.DrawArc($pen, 47, 77, 162, 91, 0, 180)
    $graphics.DrawLine($pen, 67, 153, 54, 175)
    $graphics.DrawLine($pen, 103, 170, 98, 194)
    $graphics.DrawLine($pen, 145, 170, 150, 194)
    $graphics.DrawLine($pen, 182, 151, 197, 172)
    $graphics.DrawLine($pen, 92, 64, 177, 64)
    $graphics.DrawLine($pen, 177, 64, 159, 47)
    $graphics.DrawLine($pen, 177, 64, 159, 81)
    $bitmap.Save((Join-Path $root 'icon.png'), [Drawing.Imaging.ImageFormat]::Png)
} finally { $muted.Dispose(); $pen.Dispose(); $graphics.Dispose(); $bitmap.Dispose() }
