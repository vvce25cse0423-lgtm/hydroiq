Add-Type -AssemblyName System.Drawing

$sourcePath = 'C:\Users\Nitin\.gemini\antigravity\brain\d24b3569-91a3-4d58-8b6c-b903fd23b345\.user_uploaded\media_1792762789955_49fd829f.png'
$src = [System.Drawing.Bitmap]::FromFile($sourcePath)
$w = $src.Width
$h = $src.Height

# Save raw copy
$src.Save('assets\icons\app_icon_raw.png', [System.Drawing.Imaging.ImageFormat]::Png)

# Create 32-bit ARGB image for transparency processing
$target = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($target)
$g.DrawImage($src, 0, 0, $w, $h)
$g.Dispose()
$src.Dispose()

# Lock bits
$rect = [System.Drawing.Rectangle]::new(0, 0, $w, $h)
$data = $target.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadWrite, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$stride = $data.Stride
$ptr = $data.Scan0
$bytes = [byte[]]::new($stride * $h)
[System.Runtime.InteropServices.Marshal]::Copy($ptr, $bytes, 0, $bytes.Length)

# BFS flood fill from 4 corners
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

    # White background threshold
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
$target.UnlockBits($data)

# Save main assets (1024x1024)
$target.Save('assets\icons\app_icon.png', [System.Drawing.Imaging.ImageFormat]::Png)
$target.Save('assets\images\app_icon.png', [System.Drawing.Imaging.ImageFormat]::Png)
Write-Output "Saved 1024x1024 icons to assets\icons and assets\images"

# Helper function to resize with high quality bicubic interpolation
function Resize-Image($img, $width, $height, $outPath) {
    $newBmp = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($newBmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.DrawImage($img, 0, 0, $width, $height)
    $g.Dispose()
    $newBmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $newBmp.Dispose()
    Write-Output "Generated $outPath (${width}x$height)"
}

# Generate 512x512 icon for Play Store
Resize-Image $target 512 512 'assets\icons\app_icon_512.png'

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
    Resize-Image $target $size $size "$dir\ic_launcher.png"
    Resize-Image $target $size $size "$dir\ic_launcher_round.png"
    Resize-Image $target $size $size "$dir\ic_launcher_foreground.png"
}

$target.Dispose()
Write-Output "All icons successfully generated!"
