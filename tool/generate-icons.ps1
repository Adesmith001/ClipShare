# Regenerate the code-drawn launcher mark on Windows. No runtime app dependency.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectRoot = Split-Path -Parent $PSScriptRoot
function Write-ClipShareIcon([string]$destination, [int]$size) {
    $bitmap = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.ColorTranslator]::FromHtml('#302435'))
    $graphics.ScaleTransform($size / 1024.0, $size / 1024.0)
    $pen = [System.Drawing.Pen]::new([System.Drawing.ColorTranslator]::FromHtml('#F5C5A5'), 76)
    $pen.StartCap = $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $clip = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $clip.AddLine(530,300,600,230)
    $clip.AddBezier(600,230,740,90,940,290,800,430)
    $clip.AddLine(800,430,700,530)
    $clip.StartFigure()
    $clip.AddLine(324,494,224,594)
    $clip.AddBezier(224,594,84,734,284,934,424,794)
    $clip.AddLine(424,794,494,724)
    $graphics.DrawPath($pen,$clip)
    $play = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $play.AddLine(430,368,430,656)
    $play.AddLine(430,656,650,512)
    $play.CloseFigure()
    $brush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#FAF7F2'))
    $graphics.FillPath($brush,$play)
    $bitmap.Save($destination,[System.Drawing.Imaging.ImageFormat]::Png)
    $clip.Dispose(); $play.Dispose(); $brush.Dispose(); $pen.Dispose(); $graphics.Dispose(); $bitmap.Dispose()
}
$androidRes = Join-Path $projectRoot 'android/app/src/main/res'
foreach ($density in @{ 'mdpi'=48; 'hdpi'=72; 'xhdpi'=96; 'xxhdpi'=144; 'xxxhdpi'=192 }.GetEnumerator()) {
    Write-ClipShareIcon (Join-Path $androidRes "mipmap-$($density.Key)/ic_launcher.png") $density.Value
}
$iosIcons = Join-Path $projectRoot 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
$catalog = Get-Content -LiteralPath (Join-Path $iosIcons 'Contents.json') -Raw | ConvertFrom-Json
foreach ($asset in $catalog.images) {
    $points = [double]::Parse(($asset.size -split 'x')[0],[Globalization.CultureInfo]::InvariantCulture)
    $scale = [int](($asset.scale -replace 'x',''))
    Write-ClipShareIcon (Join-Path $iosIcons $asset.filename) ([int]($points*$scale))
}

Write-ClipShareIcon (Join-Path $projectRoot 'assets/clipshare-icon.png') 1024
