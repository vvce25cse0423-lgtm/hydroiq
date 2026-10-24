Add-Type -AssemblyName System.Drawing

$rawSource = 'scripts\raw_assets\new_app_icon_raw.png'
if (-not (Test-Path $rawSource)) {
    Write-Error "Source image $rawSource not found!"
    exit 1
}

$src = [System.Drawing.Bitmap]::FromFile($rawSource)

# -------------------------------------------------------------
# Part 1: Crop and Enhance Icon with Thickened Circuit Traces (15-20%)
# -------------------------------------------------------------
$cropSize = 520
$cropX = [int](512 - ($cropSize / 2)) # 252
$cropY = [int](284 - ($cropSize / 2)) # 24

$cropped = New-Object System.Drawing.Bitmap($cropSize, $cropSize, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$gCrop = [System.Drawing.Graphics]::FromImage($cropped)
$gCrop.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gCrop.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$cropRect = New-Object System.Drawing.Rectangle($cropX, $cropY, $cropSize, $cropSize)
$gCrop.DrawImage($src, 0, 0, $cropRect, [System.Drawing.GraphicsUnit]::Pixel)
$gCrop.Dispose()

# Enhance golden circuit lines by 15-20% to prevent blur at micro-resolutions (40-48px)
$rect = New-Object System.Drawing.Rectangle(0, 0, $cropSize, $cropSize)
$data = $cropped.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadWrite, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$stride = $data.Stride
$ptr = $data.Scan0
$bytes = [byte[]]::new($stride * $cropSize)
[System.Runtime.InteropServices.Marshal]::Copy($ptr, $bytes, 0, $bytes.Length)

$origBytes = [byte[]]::new($bytes.Length)
[Array]::Copy($bytes, $origBytes, $bytes.Length)

# Circuit region in lower half of drop
for ($y = 230; $y -lt 430; $y++) {
    for ($x = 140; $x -lt 380; $x++) {
        $idx = ($y * $stride) + ($x * 4)
        $b = $origBytes[$idx]
        $g = $origBytes[$idx + 1]
        $r = $origBytes[$idx + 2]

        # Is this a gold circuit / synaptic node pixel?
        $isGold = ($r -gt 150 -and $g -gt 100 -and ($r - $b) -gt 35)

        if ($isGold) {
            # Brighten core and boost saturation
            $newR = [Math]::Min(255, [int]($r * 1.18))
            $newG = [Math]::Min(255, [int]($g * 1.15))
            $newB = [Math]::Max(0, [int]($b * 0.88))

            $bytes[$idx] = [byte]$newB
            $bytes[$idx + 1] = [byte]$newG
            $bytes[$idx + 2] = [byte]$newR

            # Expand line width by 15-20% into adjacent background pixels
            $dx = @(1, -1, 0, 0)
            $dy = @(0, 0, 1, -1)
            for ($k = 0; $k -lt 4; $k++) {
                $nx = $x + $dx[$k]
                $ny = $y + $dy[$k]
                if ($nx -ge 140 -and $nx -lt 380 -and $ny -ge 230 -and $ny -lt 430) {
                    $nidx = ($ny * $stride) + ($nx * 4)
                    $nb = $origBytes[$nidx]
                    $ng = $origBytes[$nidx + 1]
                    $nr = $origBytes[$nidx + 2]
                    $nIsGold = ($nr -gt 150 -and $ng -gt 100 -and ($nr - $nb) -gt 35)
                    if (-not $nIsGold) {
                        $bytes[$nidx + 2] = [byte][Math]::Min(255, [int]($nr * 0.75 + $newR * 0.25))
                        $bytes[$nidx + 1] = [byte][Math]::Min(255, [int]($ng * 0.75 + $newG * 0.25))
                        $bytes[$nidx] = [byte][Math]::Min(255, [int]($nb * 0.85 + $newB * 0.15))
                    }
                }
            }
        }
    }
}

[System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $ptr, $bytes.Length)
$cropped.UnlockBits($data)

# Create 1024x1024 full-bleed background
$bg1024 = New-Object System.Drawing.Bitmap(1024, 1024, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$gBg = [System.Drawing.Graphics]::FromImage($bg1024)
$bgRect = New-Object System.Drawing.Rectangle(0, 0, 1024, 1024)
$bgPath = New-Object System.Drawing.Drawing2D.GraphicsPath
$bgPath.AddRectangle($bgRect)

$pbr = New-Object System.Drawing.Drawing2D.PathGradientBrush($bgPath)
$pbr.CenterPoint = [System.Drawing.PointF]::new(512, 512)
$pbr.CenterColor = [System.Drawing.Color]::FromArgb(255, 6, 21, 46)
$pbr.SurroundColors = @(
    [System.Drawing.Color]::FromArgb(255, 2, 6, 20),
    [System.Drawing.Color]::FromArgb(255, 2, 6, 20),
    [System.Drawing.Color]::FromArgb(255, 1, 4, 18),
    [System.Drawing.Color]::FromArgb(255, 1, 4, 18)
)
$gBg.FillRectangle($pbr, $bgRect)
$pbr.Dispose()
$bgPath.Dispose()
$gBg.Dispose()

# Safe-zone scaled dimensions (68% scale = 696x696, 164px padding)
$scale = 0.68
$targetSize = [int](1024 * $scale)
$offset = [int]((1024 - $targetSize) / 2)

# Pre-composited full icon
$composite1024 = New-Object System.Drawing.Bitmap($bg1024)
$gComp = [System.Drawing.Graphics]::FromImage($composite1024)
$gComp.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gComp.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$gComp.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$gComp.DrawImage($cropped, $offset, $offset, $targetSize, $targetSize)
$gComp.Dispose()

# Foreground on transparent canvas (for adaptive icons)
$fg1024 = New-Object System.Drawing.Bitmap(1024, 1024, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$gFg = [System.Drawing.Graphics]::FromImage($fg1024)
$gFg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gFg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$gFg.Clear([System.Drawing.Color]::Transparent)
$gFg.DrawImage($cropped, $offset, $offset, $targetSize, $targetSize)
$gFg.Dispose()
$cropped.Dispose()

# Helper function to resize with high quality bicubic interpolation
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

# Save main Flutter assets
$composite1024.Save('assets\icons\app_icon.png', [System.Drawing.Imaging.ImageFormat]::Png)
$composite1024.Save('assets\images\app_icon.png', [System.Drawing.Imaging.ImageFormat]::Png)
Resize-Image $composite1024 512 512 'assets\icons\app_icon_512.png'

# Android mipmap densities and sizes
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

$bg1024.Dispose()
$fg1024.Dispose()
$composite1024.Dispose()
Write-Output "App icons with enhanced micro-details generated for all densities!"

# -------------------------------------------------------------
# Part 2: Generate Splash Screen Image (1080 x 2340 Portrait)
# -------------------------------------------------------------
$splashW = 1080
$splashH = 2340
$splash = New-Object System.Drawing.Bitmap($splashW, $splashH, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$gSplash = [System.Drawing.Graphics]::FromImage($splash)
$gSplash.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gSplash.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

$bgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 2, 7, 24))
$gSplash.FillRectangle($bgBrush, 0, 0, $splashW, $splashH)
$bgBrush.Dispose()

$glowPath = New-Object System.Drawing.Drawing2D.GraphicsPath
$glowRect = New-Object System.Drawing.Rectangle(0, [int]($splashH * 0.25), $splashW, [int]($splashH * 0.45))
$glowPath.AddEllipse($glowRect)
$pbrGlow = New-Object System.Drawing.Drawing2D.PathGradientBrush($glowPath)
$pbrGlow.CenterPoint = [System.Drawing.PointF]::new($splashW / 2, [float]($splashH * 0.42))
$pbrGlow.CenterColor = [System.Drawing.Color]::FromArgb(255, 6, 26, 54)
$pbrGlow.SurroundColors = @([System.Drawing.Color]::FromArgb(255, 2, 7, 24))
$gSplash.FillRectangle($pbrGlow, $glowRect)
$pbrGlow.Dispose()
$glowPath.Dispose()

$targetSrcH = [int]($splashW * (572.0 / 1024.0))
$targetSrcY = [int](($splashH - $targetSrcH) * 0.42)

$gSplash.DrawImage($src, 0, $targetSrcY, $splashW, $targetSrcH)

$sparkleX = [int](910 * ($splashW / 1024.0))
$sparkleY = [int]($targetSrcY + (460 * ($targetSrcH / 572.0)))
$sparkleW = [int](60 * ($splashW / 1024.0))
$sparkleH = [int](60 * ($targetSrcH / 572.0))
$sparkleBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 1, 4, 21))
$gSplash.FillEllipse($sparkleBrush, $sparkleX, $sparkleY, $sparkleW, $sparkleH)
$sparkleBrush.Dispose()

$gSplash.Dispose()

$splashOut = "assets\images\splash_background.jpg"
$splash.Save($splashOut, [System.Drawing.Imaging.ImageFormat]::Jpeg)
$splash.Dispose()
$src.Dispose()

Write-Output "Icons and splash regenerated successfully!"
