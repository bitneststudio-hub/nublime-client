# Save a full-screen PNG and print its path (used by the Mac side to "see" the Windows app)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
$p = Join-Path $env:TEMP ("wl-shot-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".png")
$bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output $p
