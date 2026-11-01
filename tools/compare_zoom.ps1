Add-Type -AssemblyName System.Drawing
$icon = New-Object System.Drawing.Icon('c:\Users\milaz\BetterDesk\zoom-app-logo.ico', 256, 256)
$a = $icon.ToBitmap()
$b = [System.Drawing.Bitmap]::FromFile('c:\Users\milaz\BetterDesk\zoom-4k.png')
$t = New-Object System.Drawing.Bitmap(64, 64)
$g = [System.Drawing.Graphics]::FromImage($t)
$g.DrawImage($a, 0, 0, 64, 64); $g.Dispose()
$t2 = New-Object System.Drawing.Bitmap(64, 64)
$g2 = [System.Drawing.Graphics]::FromImage($t2)
$g2.DrawImage($b, 0, 0, 64, 64); $g2.Dispose()
$diff = 0; $tot = 0
for ($y = 0; $y -lt 64; $y++) {
  for ($x = 0; $x -lt 64; $x++) {
    $p1 = $t.GetPixel($x, $y); $p2 = $t2.GetPixel($x, $y)
    $d = [Math]::Abs($p1.R - $p2.R) + [Math]::Abs($p1.G - $p2.G) + [Math]::Abs($p1.B - $p2.B)
    if ($d -gt 60) { $diff++ }
    $tot++
  }
}
Write-Output ("pixels differing: {0}/{1} ({2:P0})" -f $diff, $tot, ($diff / $tot))
Write-Output ("ico center: " + $t.GetPixel(32, 32) + " | 4k center: " + $t2.GetPixel(32, 32))
$icon.Dispose(); $a.Dispose(); $b.Dispose(); $t.Dispose(); $t2.Dispose()