Add-Type -AssemblyName System.Drawing

$src = "C:\Users\Nitin\.gemini\antigravity\brain\d24b3569-91a3-4d58-8b6c-b903fd23b345\.user_uploaded\media_1793369562571_087cbab8.png"
if (-not (Test-Path $src)) {
    Write-Error "Source file not found: $src"
    exit 1
}

# Copy raw source first
Copy-Item $src -Destination "assets\images\login_template_raw.png" -Force

$bmp = [System.Drawing.Bitmap]::FromFile($src)
$w = $bmp.Width  # 460
$h = $bmp.Height # 1024

$cleanBmp = New-Object System.Drawing.Bitmap($bmp)

# Inside the card:
# Let's clean the area where text and buttons are located:
# x from 55 to 405
# y from 380 to 785
# We can sample the clean card background color at the edges and interpolate smoothly.
$xLeft = 52
$xRight = 408
$yTop = 380
$yBottom = 785

for ($y = $yTop; $y -le $yBottom; $y++) {
    $tY = ($y - $yTop) / ($yBottom - $yTop)
    # Background inside card:
    # Top is around (221, 234, 243)
    # Middle is around (245, 249, 251)
    # Bottom is around (212, 223, 232)
    $baseR = 0
    $baseG = 0
    $baseB = 0
    if ($tY -lt 0.5) {
        $t = $tY / 0.5
        $baseR = 224 * (1 - $t) + 246 * $t
        $baseG = 235 * (1 - $t) + 249 * $t
        $baseB = 244 * (1 - $t) + 252 * $t
    } else {
        $t = ($tY - 0.5) / 0.5
        $baseR = 246 * (1 - $t) + 214 * $t
        $baseG = 249 * (1 - $t) + 224 * $t
        $baseB = 252 * (1 - $t) + 233 * $t
    }
    
    for ($x = $xLeft; $x -le $xRight; $x++) {
        # Check if inside card bounds (respecting rounded corners)
        $cleanBmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, [int]$baseR, [int]$baseG, [int]$baseB))
    }
}

# Now upscale to high-resolution 1080 x 2405 (matches 460x1024 aspect ratio)
$targetW = 1080
$targetH = [int](1080 * ($h / $w)) # 2405

$highRes = New-Object System.Drawing.Bitmap($targetW, $targetH, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$g = [System.Drawing.Graphics]::FromImage($highRes)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

$g.DrawImage($cleanBmp, 0, 0, $targetW, $targetH)
$g.Dispose()

# Save as assets\images\login_background.jpg and assets\images\login_background.png
$outJpg = "assets\images\login_background.jpg"
$outPng = "assets\images\login_background.png"

$highRes.Save($outJpg, [System.Drawing.Imaging.ImageFormat]::Jpeg)
$highRes.Save($outPng, [System.Drawing.Imaging.ImageFormat]::Png)

$highRes.Dispose()
$cleanBmp.Dispose()
$bmp.Dispose()

Write-Output "Successfully generated high-res login background ($targetW x $targetH)"
