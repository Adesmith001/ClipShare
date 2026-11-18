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
    $pen = [System.Drawing.Pen]::new([System.Drawing.ColorTranslator]::FromHtml('#F5C5A5'), 62)
    $pen.StartCap = $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $clip = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $clip.AddLine(620,340,400,560)
    $clip.AddBezier(400,560,340,620,260,540,320,480)
    $clip.AddLine(320,480,550,250)
    $clip.AddBezier(550,250,670,130,830,290,710,410)
    $clip.AddLine(710,410,440,680)
    $clip.AddBezier(440,680,260,860,40,640,220,460)
    $clip.AddLine(220,460,400,280)
    $graphics.DrawPath($pen,$clip)
    $pen.Color = [System.Drawing.ColorTranslator]::FromHtml('#FAF7F2')
    $pen.Width = 58
    $graphics.DrawLine($pen,740,560,740,800)
    $arrow = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $arrow.AddLine(650,710,740,800)
    $arrow.AddLine(740,800,830,710)
    $graphics.DrawPath($pen,$arrow)
    $bitmap.Save($destination,[System.Drawing.Imaging.ImageFormat]::Png)
    $clip.Dispose(); $arrow.Dispose(); $pen.Dispose(); $graphics.Dispose(); $bitmap.Dispose()
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
