Add-Type -AssemblyName System.Drawing

$srcSignup = "scripts\raw_assets\signup_screen_raw.png"
$bmp = [System.Drawing.Bitmap]::FromFile((Resolve-Path $srcSignup))
$w = $bmp.Width  # 460
$h = $bmp.Height # 1024

$cleanBmp = New-Object System.Drawing.Bitmap($bmp)

# The container in signup_screen_raw.png is located at:
# x: from ~35 to ~425
# y: from ~350 to ~864
# We will completely inpaint / fill this area with the natural scenery!
# Let's inspect the surrounding pixels:
# Above (y = 346): soft sky/foliage (R ~ 80-140, G ~ 150-200, B ~ 170-230)
# Left (x = 30): green foliage (R ~ 120-150, G ~ 170-200, B ~ 110-130)
# Right (x = 430): light foliage (R ~ 80-120, G ~ 160-180, B ~ 170-190)
# Below (y = 868): blue towel & wooden desk tones (R ~ 80-110, G ~ 160-180, B ~ 200-220)

for ($y = 350; $y -le 865; $y++) {
    $tY = ($y - 350.0) / (865.0 - 350.0) # 0.0 at top, 1.0 at bottom
    
    # Sample left and right scenery pixels at this y
    $cLeft = $bmp.GetPixel(30, $y)
    $cRight = $bmp.GetPixel(430, $y)
    
    # Also sample top and bottom for vertical gradient influence
    $cTop = $bmp.GetPixel(230, 346)
    $cBottom = $bmp.GetPixel(230, 868)
    
    for ($x = 30; $x -le 430; $x++) {
        $tX = ($x - 30.0) / (430.0 - 30.0) # 0.0 at left, 1.0 at right
        
        # Horizontal blend between left and right scenery
        $rHoriz = $cLeft.R * (1.0 - $tX) + $cRight.R * $tX
        $gHoriz = $cLeft.G * (1.0 - $tX) + $cRight.G * $tX
        $bHoriz = $cLeft.B * (1.0 - $tX) + $cRight.B * $tX
        
        # Vertical blend between top and bottom scenery
        $rVert = $cTop.R * (1.0 - $tY) + $cBottom.R * $tY
        $gVert = $cTop.G * (1.0 - $tY) + $cBottom.G * $tY
        $bVert = $cTop.B * (1.0 - $tY) + $cBottom.B * $tY
        
        # Combine horizontal bokeh and vertical ambient lighting (60% horiz, 40% vert)
        $rFinal = [Math]::Min(255, [Math]::Max(0, [int]($rHoriz * 0.55 + $rVert * 0.45)))
        $gFinal = [Math]::Min(255, [Math]::Max(0, [int]($gHoriz * 0.55 + $gVert * 0.45)))
        $bFinal = [Math]::Min(255, [Math]::Max(0, [int]($bHoriz * 0.55 + $bVert * 0.45)))
        
        $cleanBmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, $rFinal, $gFinal, $bFinal))
    }
}

# Upscale to high-resolution 1080 x 2404
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

Write-Host "Created seamless assets\images\signup_background.jpg with NO inner container."
