Add-Type -AssemblyName System.Drawing

$srcLogin = "scripts\raw_assets\login_screen_raw.png"
$bmp = [System.Drawing.Bitmap]::FromFile((Resolve-Path $srcLogin))
$w = $bmp.Width  # 460
$h = $bmp.Height # 1024

$cleanBmp = New-Object System.Drawing.Bitmap($bmp)

# 1. Erase the top curve and border of the container in login image.
# In login_screen_raw.png, the container starts around y = 358 to 360, and ends around y = 810.
# The user saw the container at the top position inside the image.
# We will blend from y = 353 down to y = 460 across x = 30 to 430:
# For each x, sample the natural background color at y = 350-353:
$colSample = @{}
for ($x = 0; $x -lt $w; $x++) {
    $c1 = $bmp.GetPixel($x, 350)
    $c2 = $bmp.GetPixel($x, 352)
    $colSample[$x] = [System.Drawing.Color]::FromArgb(
        255,
        [int](($c1.R + $c2.R) / 2),
        [int](($c1.G + $c2.G) / 2),
        [int](($c1.B + $c2.B) / 2)
    )
}

# Fill from y = 354 down to y = 460
for ($y = 354; $y -le 460; $y++) {
    $alpha = [Math]::Min(1.0, ($y - 354) / 15.0)
    for ($x = 30; $x -le 430; $x++) {
        $cTop = $colSample[$x]
        # Soft vertical gradient towards a calm ambient wall tone
        $ambientR = [int]($cTop.R * 0.95 + 110 * 0.05)
        $ambientG = [int]($cTop.G * 0.95 + 150 * 0.05)
        $ambientB = [int]($cTop.B * 0.95 + 180 * 0.05)
        $cleanBmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, $ambientR, $ambientG, $ambientB))
    }
}

# Now upscale to high-resolution 1080 x 2404
$targetW = 1080
$targetH = 2404

$highRes = New-Object System.Drawing.Bitmap($targetW, $targetH, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$g = [System.Drawing.Graphics]::FromImage($highRes)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

$g.DrawImage($cleanBmp, 0, 0, $targetW, $targetH)
$g.Dispose()

# Save with JPEG encoder quality 90
$jpegEncoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
$encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]90)

$outPath = "assets\images\login_background.jpg"
$highRes.Save((Resolve-Path -Path $outPath), $jpegEncoder, $encoderParams)

$highRes.Dispose()
$cleanBmp.Dispose()
$bmp.Dispose()

Write-Host "Updated assets\images\login_background.jpg successfully."
