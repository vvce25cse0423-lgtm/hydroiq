Add-Type -AssemblyName System.Drawing

$rawSource = 'scripts\raw_assets\new_app_icon_raw.png'
if (-not (Test-Path $rawSource)) {
    Write-Error "Source image $rawSource not found!"
    exit 1
}

$src = [System.Drawing.Bitmap]::FromFile($rawSource)
$w = $src.Width
$h = $src.Height

Write-Output "Processing source icon ($w x $h)..."

# -------------------------------------------------------------
# Step 1: Clean White Corners from the Icon
# -------------------------------------------------------------
$cleanBtn = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$gClean = [System.Drawing.Graphics]::FromImage($cleanBtn)
$gClean.DrawImage($src, 0, 0, $w, $h)
$gClean.Dispose()

$rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
$data = $cleanBtn.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadWrite, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$stride = $data.Stride
$ptr = $data.Scan0
$bytes = [byte[]]::new($stride * $h)
[System.Runtime.InteropServices.Marshal]::Copy($ptr, $bytes, 0, $bytes.Length)

# Flood fill from 4 corners for outer white pixels
$visited = New-Object "bool[,]" $w, $h
$queue = New-Object System.Collections.Generic.Queue[System.Drawing.Point]

$seeds = @(
    [System.Drawing.Point]::new(0, 0),
    [System.Drawing.Point]::new($w - 1, 0),
    [System.Drawing.Point]::new(0, $h - 1),
    [System.Drawing.Point]::new($w - 1, $h - 1)
)
foreach ($s in $seeds) {
    $queue.Enqueue($s)
    $visited[$s.X, $s.Y] = $true
}

$dx = @(1, -1, 0, 0)
$dy = @(0, 0, 1, -1)

while ($queue.Count -gt 0) {
    $pt = $queue.Dequeue()
    $idx = ($pt.Y * $stride) + ($pt.X * 4)
    $b = $bytes[$idx]
    $gVal = $bytes[$idx + 1]
    $r = $bytes[$idx + 2]

    # White corner threshold
    if ($r -gt 225 -and $gVal -gt 225 -and $b -gt 225) {
        $bytes[$idx + 3] = 0 # Transparent
        for ($i = 0; $i -lt 4; $i++) {
            $nx = $pt.X + $dx[$i]
            $ny = $pt.Y + $dy[$i]
            if ($nx -ge 0 -and $nx -lt $w -and $ny -ge 0 -and $ny -lt $h) {
                if (-not $visited[$nx, $ny]) {
                    $visited[$nx, $ny] = $true
                    $queue.Enqueue([System.Drawing.Point]::new($nx, $ny))
                }
            }
        }
    }
}

[System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $ptr, $bytes.Length)
$cleanBtn.UnlockBits($data)

# -------------------------------------------------------------
# Step 2: Full-Bleed Royal Blue Background (1024x1024)
# -------------------------------------------------------------
$bg1024 = New-Object System.Drawing.Bitmap(1024, 1024, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$gBg = [System.Drawing.Graphics]::FromImage($bg1024)
$bgRect = New-Object System.Drawing.Rectangle(0, 0, 1024, 1024)
$bgPath = New-Object System.Drawing.Drawing2D.GraphicsPath
$bgPath.AddRectangle($bgRect)

$pbr = New-Object System.Drawing.Drawing2D.PathGradientBrush($bgPath)
$pbr.CenterPoint = [System.Drawing.PointF]::new(512, 490)
$pbr.CenterColor = [System.Drawing.Color]::FromArgb(255, 8, 103, 234) # Vibrant royal blue
$pbr.SurroundColors = @(
    [System.Drawing.Color]::FromArgb(255, 6, 75, 190),  # Top-Left
    [System.Drawing.Color]::FromArgb(255, 12, 110, 245), # Top-Right
    [System.Drawing.Color]::FromArgb(255, 2, 40, 130),  # Bottom-Right
    [System.Drawing.Color]::FromArgb(255, 2, 40, 130)   # Bottom-Left
)
$gBg.FillRectangle($pbr, $bgRect)
$pbr.Dispose()
$bgPath.Dispose()
$gBg.Dispose()

# -------------------------------------------------------------
# Step 3: Scaled Composite & Adaptive Foreground (68% Safe Zone)
# -------------------------------------------------------------
$scale = 0.68
$targetSize = [int](1024 * $scale) # 696
$offset = [int]((1024 - $targetSize) / 2) # 164

# 3A: Pre-composited full icon
$composite1024 = New-Object System.Drawing.Bitmap($bg1024)
$gComp = [System.Drawing.Graphics]::FromImage($composite1024)
$gComp.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gComp.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$gComp.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$gComp.DrawImage($cleanBtn, $offset, $offset, $targetSize, $targetSize)
$gComp.Dispose()

# 3B: Adaptive foreground (transparent canvas)
$fg1024 = New-Object System.Drawing.Bitmap(1024, 1024, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$gFg = [System.Drawing.Graphics]::FromImage($fg1024)
$gFg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gFg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$gFg.Clear([System.Drawing.Color]::Transparent)
$gFg.DrawImage($cleanBtn, $offset, $offset, $targetSize, $targetSize)
$gFg.Dispose()

# Helper for resizing with high quality bicubic interpolation
function Resize-Image($img, $width, $height, $outPath) {
    $newBmp = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gResize = [System.Drawing.Graphics]::FromImage($newBmp)
    $gResize.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $gResize.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $gResize.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $gResize.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $gResize.Clear([System.Drawing.Color]::Transparent)
    $gResize.DrawImage($img, 0, 0, $width, $height)
    $gResize.Dispose()
    $newBmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $newBmp.Dispose()
}

# -------------------------------------------------------------
# Step 4: Export Main Flutter Assets
# -------------------------------------------------------------
$composite1024.Save('assets\icons\app_icon.png', [System.Drawing.Imaging.ImageFormat]::Png)
$composite1024.Save('assets\images\app_icon.png', [System.Drawing.Imaging.ImageFormat]::Png)
Resize-Image $composite1024 512 512 'assets\icons\app_icon_512.png'
Write-Output "Flutter icon assets saved (1024x1024 and 512x512)."

# -------------------------------------------------------------
# Step 5: Export Android Mipmap Densities
# -------------------------------------------------------------
$densities = @(
    @{ Name = 'mdpi'; Size = 48 },
    @{ Name = 'hdpi'; Size = 72 },
    @{ Name = 'xhdpi'; Size = 96 },
    @{ Name = 'xxhdpi'; Size = 144 },
    @{ Name = 'xxxhdpi'; Size = 192 }
)

foreach ($d in $densities) {
    $dir = "android\app\src\main\res\mipmap-$($d.Name)"
    $size = $d.Size
    Resize-Image $composite1024 $size $size "$dir\ic_launcher.png"
    Resize-Image $composite1024 $size $size "$dir\ic_launcher_round.png"
    Resize-Image $fg1024 $size $size "$dir\ic_launcher_foreground.png"
    Resize-Image $bg1024 $size $size "$dir\ic_launcher_background.png"
}
Write-Output "Android mipmaps generated for all densities."

# -------------------------------------------------------------
# Step 6: Generate High-Resolution Splash Screen (1080 x 2340 Portrait)
# -------------------------------------------------------------
$splashW = 1080
$splashH = 2340
$splash = New-Object System.Drawing.Bitmap($splashW, $splashH, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$gSplash = [System.Drawing.Graphics]::FromImage($splash)
$gSplash.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gSplash.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$gSplash.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

# Deep midnight blue canvas
$bgSplashBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 3, 10, 28))
$gSplash.FillRectangle($bgSplashBrush, 0, 0, $splashW, $splashH)
$bgSplashBrush.Dispose()

# Soft vibrant royal blue ambient glow centered on the logo
$glowPath = New-Object System.Drawing.Drawing2D.GraphicsPath
$glowRect = New-Object System.Drawing.Rectangle(0, [int]($splashH * 0.22), $splashW, [int]($splashH * 0.40))
$glowPath.AddEllipse($glowRect)
$pbrGlow = New-Object System.Drawing.Drawing2D.PathGradientBrush($glowPath)
$pbrGlow.CenterPoint = [System.Drawing.PointF]::new($splashW / 2, [float]($splashH * 0.40))
$pbrGlow.CenterColor = [System.Drawing.Color]::FromArgb(255, 8, 48, 120)
$pbrGlow.SurroundColors = @([System.Drawing.Color]::FromArgb(255, 3, 10, 28))
$gSplash.FillRectangle($pbrGlow, $glowRect)
$pbrGlow.Dispose()
$glowPath.Dispose()

# Draw clean Hydro H icon centered at Y ~ 38%
$iconSplashSize = 460
$iconSplashX = [int](($splashW - $iconSplashSize) / 2)
$iconSplashY = [int]($splashH * 0.30)
$gSplash.DrawImage($cleanBtn, $iconSplashX, $iconSplashY, $iconSplashSize, $iconSplashSize)

# Branding Text: "HydroIQ"
$fontFamily = New-Object System.Drawing.FontFamily("Segoe UI")
$titleFont = New-Object System.Drawing.Font($fontFamily, 44, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$titleBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 255, 255, 255))
$stringFormat = New-Object System.Drawing.StringFormat
$stringFormat.Alignment = [System.Drawing.StringAlignment]::Center
$stringFormat.LineAlignment = [System.Drawing.StringAlignment]::Center

$titleY = [float]($iconSplashY + $iconSplashSize + 55)
$titleRect = New-Object System.Drawing.RectangleF(0, $titleY, [float]$splashW, 60.0)
$gSplash.DrawString("HydroIQ", $titleFont, $titleBrush, $titleRect, $stringFormat)

# Subtitle: "Intelligent Hydration Tracking"
$subFont = New-Object System.Drawing.Font($fontFamily, 18, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$subBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 120, 180, 245))
$subY = [float]($titleY + 50)
$subRect = New-Object System.Drawing.RectangleF(0, $subY, [float]$splashW, 40.0)
$gSplash.DrawString("INTELLIGENT HYDRATION TRACKING", $subFont, $subBrush, $subRect, $stringFormat)

$subBrush.Dispose()
$subFont.Dispose()
$titleBrush.Dispose()
$titleFont.Dispose()
$fontFamily.Dispose()
$stringFormat.Dispose()
$gSplash.Dispose()

$splashOut = "assets\images\splash_background.jpg"
$splash.Save($splashOut, [System.Drawing.Imaging.ImageFormat]::Jpeg)
$splash.Dispose()
Write-Output "Splash background updated at $splashOut."

# Clean up resources
$bg1024.Dispose()
$fg1024.Dispose()
$composite1024.Dispose()
$cleanBtn.Dispose()
$src.Dispose()

Write-Output "All icons and splash screen successfully updated!"
