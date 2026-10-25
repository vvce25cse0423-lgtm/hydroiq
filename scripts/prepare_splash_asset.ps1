Add-Type -AssemblyName System.Drawing

$srcPath = "C:\Users\Nitin\.gemini\antigravity\brain\d24b3569-91a3-4d58-8b6c-b903fd23b345\.user_uploaded\media_1792902152187_186396d2.png"
if (-not (Test-Path $srcPath)) {
    Write-Error "Source image not found: $srcPath"
    exit 1
}

$rawDest = "scripts\raw_assets\splash_screen_raw.png"
Copy-Item $srcPath -Destination $rawDest -Force
Copy-Item $srcPath -Destination "assets\images\splash_background_raw.png" -Force

$img = [System.Drawing.Bitmap]::FromFile($srcPath)
$w = $img.Width
$h = $img.Height

Write-Output "Source splash dimensions: $w x $h"

# Clean the static loading bar & text region (Y=836 to Y=954)
$cleanImg = New-Object System.Drawing.Bitmap($img)

$yStart = 836
$yEnd = 954

for ($y = $yStart; $y -le $yEnd; $y++) {
    $tY = ($y - $yStart) / ($yEnd - $yStart)
    for ($x = 0; $x -lt $w; $x++) {
        $cTop = $img.GetPixel($x, $yStart - 1)
        $cBot = $img.GetPixel($x, $yEnd + 1)
        
        $r = [int]($cTop.R * (1 - $tY) + $cBot.R * $tY)
        $g = [int]($cTop.G * (1 - $tY) + $cBot.G * $tY)
        $b = [int]($cTop.B * (1 - $tY) + $cBot.B * $tY)
        
        $cleanImg.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, $r, $g, $b))
    }
}

# Upscale to high resolution (1080 x 1934) with high quality bicubic interpolation
$targetW = 1080
$targetH = [int](1080 * ($h / $w)) # 1934

$highRes = New-Object System.Drawing.Bitmap($targetW, $targetH, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$gHigh = [System.Drawing.Graphics]::FromImage($highRes)
$gHigh.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gHigh.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$gHigh.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$gHigh.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

$gHigh.DrawImage($cleanImg, 0, 0, $targetW, $targetH)
$gHigh.Dispose()

# Save both JPG and PNG
$outJpg = "assets\images\splash_background.jpg"
$outPng = "assets\images\splash_background.png"

$highRes.Save($outJpg, [System.Drawing.Imaging.ImageFormat]::Jpeg)
$highRes.Save($outPng, [System.Drawing.Imaging.ImageFormat]::Png)

$highRes.Dispose()
$cleanImg.Dispose()
$img.Dispose()

Write-Output "Successfully generated high-resolution splash backgrounds: $outJpg and $outPng"
