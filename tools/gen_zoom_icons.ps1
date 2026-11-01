Add-Type -AssemblyName System.Drawing

$icoPath = "c:\Users\milaz\BetterDesk\zoom-app-logo.ico"
$png4k   = "c:\Users\milaz\BetterDesk\zoom-4k.png"
$resRoot = "c:\Users\milaz\BetterDesk\flutter\android\app\src\main\res"

# --- 1. Load source image: the zoom .ico (per project branding decision) ---
$icon = New-Object System.Drawing.Icon($icoPath, 256, 256)
$src = $icon.ToBitmap()
Write-Output "ICO extracted: $($src.Width)x$($src.Height)"

function New-Size([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    return @($bmp, $g)
}

function Save-Size($src, [int]$size, [string]$path) {
    $r = New-Size $size
    $bmp = $r[0]; $g = $r[1]
    $g.DrawImage($src, 0, 0, $size, $size)
    $g.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Output "  wrote $path"
}

# --- 2. Legacy launcher icons (pre-Android 8): full-bleed square ---
$legacy = @{ "mipmap-mdpi"=48; "mipmap-hdpi"=72; "mipmap-xhdpi"=96; "mipmap-xxhdpi"=144; "mipmap-xxxhdpi"=192 }
foreach ($dir in $legacy.Keys) {
    $target = Join-Path $resRoot $dir
    # remove old XML placeholders (duplicate resource names would fail AAPT)
    Remove-Item (Join-Path $target "ic_launcher.xml"), (Join-Path $target "ic_launcher_round.xml") -Force -ErrorAction SilentlyContinue
    Save-Size $src $legacy[$dir] (Join-Path $target "ic_launcher.png")
    Save-Size $src $legacy[$dir] (Join-Path $target "ic_launcher_round.png")
}

# --- 3. Adaptive icon foreground: 108dp canvas @4x = 432px, logo in inner 66% ---
$fgDir = Join-Path $resRoot "drawable-nodpi"
New-Item -ItemType Directory -Force -Path $fgDir | Out-Null
$canvas = 432
$inner  = [int]($canvas * 0.66)   # adaptive-icon safe zone
$r = New-Size $canvas
$bmp = $r[0]; $g = $r[1]
$g.DrawImage($src, [int](($canvas - $inner)/2), [int](($canvas - $inner)/2), $inner, $inner)
$g.Dispose()
$bmp.Save((Join-Path $fgDir "ic_launcher_foreground.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "  wrote $fgDir\ic_launcher_foreground.png ($canvas px)"

$src.Dispose()
Write-Output "DONE"