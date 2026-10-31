Add-Type -AssemblyName System.Drawing

$srcSignup = "scripts\raw_assets\signup_screen_raw.png"
$bmp = [System.Drawing.Bitmap]::FromFile((Resolve-Path $srcSignup))
$w = $bmp.Width  # 460
$h = $bmp.Height # 1024

$cleanBmp = New-Object System.Drawing.Bitmap($bmp)

# Sample background color around divider y = 346-348 across width
$colSample = @{}
for ($x = 0; $x -lt $w; $x++) {
    $c1 = $bmp.GetPixel($x, 346)
    $c2 = $bmp.GetPixel($x, 348)
    $colSample[$x] = [System.Drawing.Color]::FromArgb(
        255,
        [int](($c1.R + $c2.R) / 2),
        [int](($c1.G + $c2.G) / 2),
        [int](($c1.B + $c2.B) / 2)
    )
}

# Fill/blend from y = 350 down to y = 460 across container width (x: 25 to 435)
for ($y = 350; $y -le 460; $y++) {
    for ($x = 25; $x -le 435; $x++) {
        $cTop = $colSample[$x]
        $cleanBmp.SetPixel($x, $y, $cTop)
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

$outPath = "assets\images\signup_background.jpg"
$highRes.Save($outPath, $jpegEncoder, $encoderParams)

$highRes.Dispose()
$cleanBmp.Dispose()
$bmp.Dispose()

Write-Host "Created assets\images\signup_background.jpg successfully."
