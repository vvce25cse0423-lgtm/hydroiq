Add-Type -AssemblyName System.Drawing

$sourcePath = 'scripts\raw_assets\app_icon_raw.png'
if (-not (Test-Path $sourcePath)) {
    Write-Error "Source image $sourcePath not found!"
    exit 1
}

$src = [System.Drawing.Bitmap]::FromFile($sourcePath)
$w = $src.Width
$h = $src.Height

# Step 1: Extract button with transparent outer white border
$btnTarget = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($btnTarget)
$g.DrawImage($src, 0, 0, $w, $h)
$g.Dispose()
$src.Dispose()

$rect = [System.Drawing.Rectangle]::new(0, 0, $w, $h)
$data = $btnTarget.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadWrite, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$stride = $data.Stride
$ptr = $data.Scan0
$bytes = [byte[]]::new($stride * $h)
[System.Runtime.InteropServices.Marshal]::Copy($ptr, $bytes, 0, $bytes.Length)

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

    if ($r -gt 230 -and $gVal -gt 230 -and $b -gt 230) {
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
$btnTarget.UnlockBits($data)

# Step 2: Create full-bleed gradient background matching the HydroIQ theme
# Radial gradient from bright blue center (#2079BB) to deep navy corners (#0A1E3E)
$bg1024 = New-Object System.Drawing.Bitmap(1024, 1024, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$gBg = [System.Drawing.Graphics]::FromImage($bg1024)
$bgRect = New-Object System.Drawing.Rectangle(0, 0, 1024, 1024)
$bgPath = New-Object System.Drawing.Drawing2D.GraphicsPath
$bgPath.AddRectangle($bgRect)

$pbr = New-Object System.Drawing.Drawing2D.PathGradientBrush($bgPath)
$pbr.CenterPoint = [System.Drawing.PointF]::new(512, 470)
$pbr.CenterColor = [System.Drawing.Color]::FromArgb(255, 32, 121, 187) # #2079BB
$pbr.SurroundColors = @(
    [System.Drawing.Color]::FromArgb(255, 12, 38, 74),  # Top-Left
    [System.Drawing.Color]::FromArgb(255, 20, 80, 130), # Top-Right
    [System.Drawing.Color]::FromArgb(255, 10, 30, 62),  # Bottom-Right
    [System.Drawing.Color]::FromArgb(255, 10, 30, 62)   # Bottom-Left
)
$gBg.FillRectangle($pbr, $bgRect)
$pbr.Dispose()
$bgPath.Dispose()
$gBg.Dispose()

# Step 3: Scale button to fit safely inside the Android Adaptive Icon safe zone (~65% scale)
$scale = 0.65
$targetW = [int](1024 * $scale)
$targetH = [int](1024 * $scale)
$offsetX = [int]((1024 - $targetW) / 2)
$offsetY = [int]((1024 - $targetH) / 2)

# 3A: Foreground (scaled button on transparent canvas for adaptive icons)
$fg1024 = New-Object System.Drawing.Bitmap(1024, 1024, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$gFg = [System.Drawing.Graphics]::FromImage($fg1024)
$gFg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gFg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$gFg.Clear([System.Drawing.Color]::Transparent)
$gFg.DrawImage($btnTarget, $offsetX, $offsetY, $targetW, $targetH)
$gFg.Dispose()

# 3B: Pre-composited full icon (background + scaled foreground)
$composite1024 = New-Object System.Drawing.Bitmap($bg1024)
$gComp = [System.Drawing.Graphics]::FromImage($composite1024)
$gComp.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gComp.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$gComp.DrawImage($btnTarget, $offsetX, $offsetY, $targetW, $targetH)
$gComp.Dispose()

$btnTarget.Dispose()

# Helper function to resize with high-quality bicubic interpolation
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

Write-Output "Successfully generated safe-zone scaled icons for all Android densities!"
