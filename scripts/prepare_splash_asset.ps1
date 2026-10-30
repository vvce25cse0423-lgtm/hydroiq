Add-Type -AssemblyName System.Drawing

$srcPath = "C:\Users\Nitin\.gemini\antigravity\brain\d24b3569-91a3-4d58-8b6c-b903fd23b345\.user_uploaded\media_1793357378288_16d9e62f.png"
$img = [System.Drawing.Bitmap]::FromFile($srcPath)
$w = $img.Width # 460
$h = $img.Height # 1024

$cleanImg = New-Object System.Drawing.Bitmap($img)

# In the 460 x 1024 image:
# Bar is at y = 866 to 888.
# Text is around y = 905 to 915.
# Let's clean from yStart = 855 to yEnd = 925
$yStart = 855
$yEnd = 925

for ($y = $yStart; $y -le $yEnd; $y++) {
    $tY = ($y - $yStart) / ($yEnd - $yStart)
    # Cosine smoothing for natural transition
    $smoothT = (1.0 - [math]::Cos($tY * [math]::PI)) / 2.0
    
    for ($x = 0; $x -lt $w; $x++) {
        $cTop = $img.GetPixel($x, $yStart - 1)
        $cBot = $img.GetPixel($x, $yEnd + 1)
        
        $r = [int]($cTop.R * (1 - $smoothT) + $cBot.R * $smoothT)
        $g = [int]($cTop.G * (1 - $smoothT) + $cBot.G * $smoothT)
        $b = [int]($cTop.B * (1 - $smoothT) + $cBot.B * $smoothT)
        
        $cleanImg.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, $r, $g, $b))
    }
}

# Upscale to standard 1080 x 2405 (matches standard 19.5:9 phone screens and 460x1024 aspect ratio)
$targetW = 1080
$targetH = [int](1080 * ($h / $w)) # 2405

$highRes = New-Object System.Drawing.Bitmap($targetW, $targetH, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$gHigh = [System.Drawing.Graphics]::FromImage($highRes)
$gHigh.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gHigh.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$gHigh.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$gHigh.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

$gHigh.DrawImage($cleanImg, 0, 0, $targetW, $targetH)
$gHigh.Dispose()

# Save
$outJpg = "assets\images\splash_background.jpg"
$outPng = "assets\images\splash_background.png"

$highRes.Save($outJpg, [System.Drawing.Imaging.ImageFormat]::Jpeg)
$highRes.Save($outPng, [System.Drawing.Imaging.ImageFormat]::Png)

$highRes.Dispose()
$cleanImg.Dispose()
$img.Dispose()

Write-Output "Generated clean high-res splash: $targetW x $targetH"
