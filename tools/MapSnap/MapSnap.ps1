# MapSnap - a standalone screen snapshot, annotation and range-measuring tool for Windows.
# It does not read game memory or send input to any other application.

Set-StrictMode -Version Latest

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if ($null -eq ('MapSnap.Native.HotKeyWindow' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace MapSnap.Native
{
    public sealed class HotKeyWindow : NativeWindow, IDisposable
    {
        private const int WM_HOTKEY = 0x0312;
        private const int HotKeyId = 1;
        private const uint VK_F8 = 0x77;

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        public event EventHandler Pressed;

        public HotKeyWindow()
        {
            CreateHandle(new CreateParams());
            if (!RegisterHotKey(Handle, HotKeyId, 0, VK_F8))
                throw new InvalidOperationException("F8 is already used by another application.");
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_HOTKEY && m.WParam.ToInt32() == HotKeyId)
            {
                EventHandler handler = Pressed;
                if (handler != null) handler(this, EventArgs.Empty);
            }
            base.WndProc(ref m);
        }

        public void Dispose()
        {
            UnregisterHotKey(Handle, HotKeyId);
            DestroyHandle();
        }
    }
}
'@ -ReferencedAssemblies System.Windows.Forms
}

[System.Windows.Forms.Application]::EnableVisualStyles()

$script:shot = $null
$script:markers = @()        # measurement points in image pixels; first = player
$script:calibPts = @()       # calibration clicks in image pixels (max 2)
$script:calibrating = $false
$script:mPerPx = $null       # meters per image pixel, set by calibration
$script:hotkey = $null

$MORTAR_MIN = 100.0
$MORTAR_MAX = 700.0
$RUN_MS = 6.3

$colOrange = [System.Drawing.Color]::FromArgb(255, 242, 160, 61)
$colCyan   = [System.Drawing.Color]::FromArgb(255, 40, 210, 255)
$colGood   = [System.Drawing.Color]::FromArgb(255, 155, 214, 91)
$colWarn   = [System.Drawing.Color]::FromArgb(255, 232, 106, 91)

$form = New-Object System.Windows.Forms.Form
$form.Text = 'MapSnap — F8 จับภาพแผนที่ + วัดระยะ'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(1100, 760)
$form.MinimumSize = New-Object System.Drawing.Size(760, 520)
$form.KeyPreview = $true
$form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)

$toolbar = New-Object System.Windows.Forms.FlowLayoutPanel
$toolbar.Dock = 'Top'
$toolbar.Height = 48
$toolbar.Padding = New-Object System.Windows.Forms.Padding(8, 8, 8, 4)
$toolbar.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)

$btnCapture = New-Object System.Windows.Forms.Button
$btnCapture.Text = 'จับภาพ (F8)'
$btnCapture.AutoSize = $true

$btnMinimize = New-Object System.Windows.Forms.Button
$btnMinimize.Text = 'ย่อไปที่เกม'
$btnMinimize.AutoSize = $true

$btnCalib = New-Object System.Windows.Forms.Button
$btnCalib.Text = 'คาลิเบรต (K)'
$btnCalib.AutoSize = $true
$btnCalib.Enabled = $false

$lblMeters = New-Object System.Windows.Forms.Label
$lblMeters.Text = 'ระยะที่ลาก ='
$lblMeters.ForeColor = [System.Drawing.Color]::Gainsboro
$lblMeters.AutoSize = $true
$lblMeters.Padding = New-Object System.Windows.Forms.Padding(6, 6, 0, 0)

$numMeters = New-Object System.Windows.Forms.NumericUpDown
$numMeters.Minimum = 50
$numMeters.Maximum = 5000
$numMeters.Increment = 50
$numMeters.Value = 100
$numMeters.Width = 70

$lblMeters2 = New-Object System.Windows.Forms.Label
$lblMeters2.Text = 'ม.'
$lblMeters2.ForeColor = [System.Drawing.Color]::Gainsboro
$lblMeters2.AutoSize = $true
$lblMeters2.Padding = New-Object System.Windows.Forms.Padding(2, 6, 8, 0)

$btnClear = New-Object System.Windows.Forms.Button
$btnClear.Text = 'ล้างจุด (C)'
$btnClear.AutoSize = $true
$btnClear.Enabled = $false

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = 'บันทึก PNG'
$btnSave.AutoSize = $true
$btnSave.Enabled = $false

$toolbar.Controls.AddRange(@($btnCapture, $btnMinimize, $btnCalib, $lblMeters, $numMeters, $lblMeters2, $btnClear, $btnSave))

$status = New-Object System.Windows.Forms.Label
$status.Dock = 'Bottom'
$status.Height = 46
$status.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 6)
$status.ForeColor = [System.Drawing.Color]::Gainsboro
$status.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)
$status.Text = 'ย่อหน้าต่างนี้ไว้ แล้วกด F8 ขณะเปิดแผนที่ใน PUBG (ซูมแมพให้เห็นเส้นตารางอย่างน้อย 2-3 ช่อง)'

$picture = New-Object System.Windows.Forms.PictureBox
$picture.Dock = 'Fill'
$picture.BackColor = [System.Drawing.Color]::Black
$picture.SizeMode = 'Zoom'
$picture.Cursor = [System.Windows.Forms.Cursors]::Cross

$form.Controls.Add($picture)
$form.Controls.Add($toolbar)
$form.Controls.Add($status)

function Get-ImageView {
    if ($null -eq $script:shot -or $picture.ClientSize.Width -le 0 -or $picture.ClientSize.Height -le 0) {
        return $null
    }

    $scaleX = $picture.ClientSize.Width / [double]$script:shot.Width
    $scaleY = $picture.ClientSize.Height / [double]$script:shot.Height
    $scale = [Math]::Min($scaleX, $scaleY)
    $drawWidth = $script:shot.Width * $scale
    $drawHeight = $script:shot.Height * $scale

    return [PSCustomObject]@{
        Scale = $scale
        Left = ($picture.ClientSize.Width - $drawWidth) / 2
        Top = ($picture.ClientSize.Height - $drawHeight) / 2
        Right = ($picture.ClientSize.Width + $drawWidth) / 2
        Bottom = ($picture.ClientSize.Height + $drawHeight) / 2
    }
}

function Get-PxDistance {
    param($A, $B)
    return [Math]::Sqrt((($A.X - $B.X) * ($A.X - $B.X)) + (($A.Y - $B.Y) * ($A.Y - $B.Y)))
}

function Format-Meters {
    param([double]$M)
    return ('{0:N0} ม.' -f [Math]::Round($M))
}

function Get-Summary {
    # returns lines of text describing total / direct / zeroing / mortar, or $null
    if ($script:markers.Count -lt 2 -or $null -eq $script:mPerPx) { return $null }

    $total = 0.0
    for ($i = 1; $i -lt $script:markers.Count; $i++) {
        $total += (Get-PxDistance $script:markers[$i - 1] $script:markers[$i]) * $script:mPerPx
    }
    $direct = (Get-PxDistance $script:markers[0] $script:markers[$script:markers.Count - 1]) * $script:mPerPx

    $zero = [Math]::Min(1000, [Math]::Max(100, [Math]::Ceiling($direct / 100.0) * 100))
    if ($direct -lt $MORTAR_MIN) { $mortar = 'ใกล้เกิน (<100)' }
    elseif ($direct -gt $MORTAR_MAX) { $mortar = 'ไกลเกิน (>700)' }
    else { $mortar = ('ตั้ง {0:N0} ม.' -f [Math]::Round($direct)) }

    $runSec = [Math]::Round($total / $RUN_MS)
    if ($runSec -lt 60) { $run = "$runSec วิ" } else { $run = ('{0}:{1:00} นาที' -f [Math]::Floor($runSec / 60), ($runSec % 60)) }

    $line1 = 'รวม ' + (Format-Meters $total)
    if ($script:markers.Count -gt 2) { $line1 += ' | ยิงตรง ' + (Format-Meters $direct) }
    $line1 += ' | วิ่ง ' + $run
    $line2 = 'Zeroing ' + ('{0:N0}' -f $zero) + ' | ปืนค. ' + $mortar
    return @($line1, $line2)
}

function Update-Controls {
    $hasShot = $null -ne $script:shot
    $btnCalib.Enabled = $hasShot
    $btnClear.Enabled = $hasShot -and ($script:markers.Count -gt 0 -or $script:calibPts.Count -gt 0)
    $btnSave.Enabled = $hasShot
}

function Update-Status {
    if ($null -eq $script:shot) {
        $status.Text = 'ย่อหน้าต่างนี้ไว้ แล้วกด F8 ขณะเปิดแผนที่ใน PUBG (ซูมแมพให้เห็นเส้นตารางอย่างน้อย 2-3 ช่อง)'
        return
    }
    if ($script:calibrating) {
        if ($script:calibPts.Count -eq 0) {
            $status.Text = 'คาลิเบรต: คลิกบน "เส้นตาราง" ของแมพเส้นแรก (ช่องเล็ก 1 ช่อง = 100 ม. — ลากข้ามหลายช่องแล้วตั้งตัวเลขเป็นระยะรวมจะแม่นขึ้น)'
        } else {
            $status.Text = 'คาลิเบรต: คลิกเส้นตารางอีกเส้น แล้วระยะระหว่างสองคลิก = ' + $numMeters.Value + ' ม. ตามช่องขวาบน'
        }
        return
    }
    if ($null -eq $script:mPerPx) {
        $status.Text = 'ยังไม่ตั้งสเกล — กด "คาลิเบรต (K)" แล้วคลิกเส้นตาราง 2 เส้นที่ติดกัน (1 ช่องเล็ก = 100 ม.)'
        return
    }
    $summary = Get-Summary
    if ($null -eq $summary) {
        $status.Text = ('สเกลพร้อม (1 px = {0:N2} ม.) — คลิกซ้ายจุดแรก = ตำแหน่งเรา, คลิกต่อ = จุดที่มาร์ค | คลิกขวา: ลบจุด | K: คาลิเบรตใหม่' -f $script:mPerPx)
    } else {
        $status.Text = ($summary -join '   ||   ')
    }
}

function Draw-Tag {
    param(
        [System.Drawing.Graphics]$Graphics,
        [double]$X,
        [double]$Y,
        [string]$Text,
        [System.Drawing.Color]$Color,
        [double]$Scale = 1
    )
    $font = New-Object System.Drawing.Font('Segoe UI', [Math]::Max(8, 10 * $Scale), [System.Drawing.FontStyle]::Bold)
    $bg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(205, 20, 20, 20))
    $fg = New-Object System.Drawing.SolidBrush($Color)
    try {
        $size = $Graphics.MeasureString($Text, $font)
        $Graphics.FillRectangle($bg, [single]($X - $size.Width / 2 - 4), [single]($Y - $size.Height / 2 - 2), [single]($size.Width + 8), [single]($size.Height + 4))
        $Graphics.DrawString($Text, $font, $fg, [single]($X - $size.Width / 2), [single]($Y - $size.Height / 2))
    }
    finally {
        $font.Dispose(); $bg.Dispose(); $fg.Dispose()
    }
}

function Draw-Annotations {
    # Draws calibration line, measurement path and points.
    # Image pixel (px,py) maps to screen (OffsetX + px*Scale, OffsetY + py*Scale).
    param(
        [System.Drawing.Graphics]$Graphics,
        [double]$OffsetX,
        [double]$OffsetY,
        [double]$Scale
    )
    $Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    # calibration
    if ($script:calibPts.Count -gt 0) {
        $pen = New-Object System.Drawing.Pen($colCyan, [Math]::Max(1.5, 1.5 * $Scale))
        try {
            foreach ($p in $script:calibPts) {
                $x = $OffsetX + $p.X * $Scale; $y = $OffsetY + $p.Y * $Scale
                $Graphics.DrawLine($pen, [single]($x - 7), [single]$y, [single]($x + 7), [single]$y)
                $Graphics.DrawLine($pen, [single]$x, [single]($y - 7), [single]$x, [single]($y + 7))
            }
            if ($script:calibPts.Count -eq 2) {
                $a = $script:calibPts[0]; $b = $script:calibPts[1]
                $pen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
                $Graphics.DrawLine($pen,
                    [single]($OffsetX + $a.X * $Scale), [single]($OffsetY + $a.Y * $Scale),
                    [single]($OffsetX + $b.X * $Scale), [single]($OffsetY + $b.Y * $Scale))
                if ($null -ne $script:mPerPx) {
                    $mx = $OffsetX + (($a.X + $b.X) / 2) * $Scale
                    $my = $OffsetY + (($a.Y + $b.Y) / 2) * $Scale - 14 * $Scale
                    Draw-Tag -Graphics $Graphics -X $mx -Y $my -Text ('สเกล ' + $numMeters.Value + ' ม.') -Color $colCyan -Scale $Scale
                }
            }
        }
        finally { $pen.Dispose() }
    }

    # measurement path with distance labels
    if ($script:markers.Count -gt 1) {
        $pen = New-Object System.Drawing.Pen($colOrange, [Math]::Max(2, 2 * $Scale))
        $pen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
        try {
            for ($i = 1; $i -lt $script:markers.Count; $i++) {
                $a = $script:markers[$i - 1]; $b = $script:markers[$i]
                $Graphics.DrawLine($pen,
                    [single]($OffsetX + $a.X * $Scale), [single]($OffsetY + $a.Y * $Scale),
                    [single]($OffsetX + $b.X * $Scale), [single]($OffsetY + $b.Y * $Scale))
                if ($null -ne $script:mPerPx) {
                    $label = Format-Meters ((Get-PxDistance $a $b) * $script:mPerPx)
                } else {
                    $label = '? ม.'
                }
                $mx = $OffsetX + (($a.X + $b.X) / 2) * $Scale
                $my = $OffsetY + (($a.Y + $b.Y) / 2) * $Scale - 13 * $Scale
                Draw-Tag -Graphics $Graphics -X $mx -Y $my -Text $label -Color $colOrange -Scale $Scale
            }
        }
        finally { $pen.Dispose() }
    }

    # points: first = player (cyan circle), rest = targets (orange cross)
    for ($i = 0; $i -lt $script:markers.Count; $i++) {
        $p = $script:markers[$i]
        $x = $OffsetX + $p.X * $Scale; $y = $OffsetY + $p.Y * $Scale
        if ($i -eq 0) {
            $fill = New-Object System.Drawing.SolidBrush($colCyan)
            $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 14, 26, 29), [Math]::Max(2, 2 * $Scale))
            try {
                $r = 8 * [Math]::Max(0.7, $Scale)
                $Graphics.FillEllipse($fill, [single]($x - $r), [single]($y - $r), [single](2 * $r), [single](2 * $r))
                $Graphics.DrawEllipse($pen, [single]($x - $r), [single]($y - $r), [single](2 * $r), [single](2 * $r))
                Draw-Tag -Graphics $Graphics -X $x -Y ($y - 20 * [Math]::Max(0.7, $Scale)) -Text 'เรา' -Color $colCyan -Scale $Scale
            }
            finally { $fill.Dispose(); $pen.Dispose() }
        } else {
            $pen = New-Object System.Drawing.Pen($colOrange, [Math]::Max(2.5, 2.5 * $Scale))
            try {
                $r = 7 * [Math]::Max(0.7, $Scale)
                $Graphics.DrawLine($pen, [single]($x - $r), [single]($y - $r), [single]($x + $r), [single]($y + $r))
                $Graphics.DrawLine($pen, [single]($x + $r), [single]($y - $r), [single]($x - $r), [single]($y + $r))
                if ($i -eq $script:markers.Count - 1) {
                    Draw-Tag -Graphics $Graphics -X $x -Y ($y - 20 * [Math]::Max(0.7, $Scale)) -Text 'เป้า' -Color $colOrange -Scale $Scale
                }
            }
            finally { $pen.Dispose() }
        }
    }

    # summary box (top-left corner of the image)
    $summary = Get-Summary
    if ($null -ne $summary) {
        $font = New-Object System.Drawing.Font('Segoe UI', [Math]::Max(9, 11 * $Scale), [System.Drawing.FontStyle]::Bold)
        $bg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(215, 20, 20, 20))
        $fg1 = New-Object System.Drawing.SolidBrush($colOrange)
        $fg2 = New-Object System.Drawing.SolidBrush($colGood)
        try {
            $s1 = $Graphics.MeasureString($summary[0], $font)
            $s2 = $Graphics.MeasureString($summary[1], $font)
            $w = [Math]::Max($s1.Width, $s2.Width) + 16
            $h = $s1.Height + $s2.Height + 12
            $Graphics.FillRectangle($bg, [single]($OffsetX + 8), [single]($OffsetY + 8), [single]$w, [single]$h)
            $Graphics.DrawString($summary[0], $font, $fg1, [single]($OffsetX + 16), [single]($OffsetY + 13))
            $Graphics.DrawString($summary[1], $font, $fg2, [single]($OffsetX + 16), [single]($OffsetY + 13 + $s1.Height + 2))
        }
        finally { $font.Dispose(); $bg.Dispose(); $fg1.Dispose(); $fg2.Dispose() }
    }
}

function Start-Calibration {
    if ($null -eq $script:shot) { return }
    $script:calibrating = $true
    $script:calibPts = @()
    $script:mPerPx = $null
    Update-Controls
    Update-Status
    $picture.Invalidate()
}

function Capture-Desktop {
    # Hiding first keeps MapSnap itself out of a capture made from this window.
    if ($form.Visible -and $form.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized) {
        $form.Hide()
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 180
    }

    $screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bitmap = New-Object System.Drawing.Bitmap($screen.Width, $screen.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($screen.Left, $screen.Top, 0, 0, $bitmap.Size)
    }
    finally {
        $graphics.Dispose()
    }

    if ($null -ne $script:shot) { $script:shot.Dispose() }
    $script:shot = $bitmap
    $script:markers = @()
    $picture.Image = $script:shot
    $form.Show()
    $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $form.Activate()
    # keep the previous scale: same game zoom level means the old calibration still holds.
    if ($null -eq $script:mPerPx) { Start-Calibration } else { Update-Controls; Update-Status }
    $picture.Invalidate()
}

$picture.add_Paint({
    param($sender, $eventArgs)
    $view = Get-ImageView
    if ($null -eq $view) { return }
    Draw-Annotations -Graphics $eventArgs.Graphics -OffsetX $view.Left -OffsetY $view.Top -Scale $view.Scale
})

$picture.add_MouseClick({
    param($sender, $eventArgs)
    $view = Get-ImageView
    if ($null -eq $view) { return }
    if ($eventArgs.X -lt $view.Left -or $eventArgs.X -gt $view.Right -or $eventArgs.Y -lt $view.Top -or $eventArgs.Y -gt $view.Bottom) { return }

    $imgX = ($eventArgs.X - $view.Left) / $view.Scale
    $imgY = ($eventArgs.Y - $view.Top) / $view.Scale

    if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        if ($script:calibrating) {
            $script:calibPts += [PSCustomObject]@{ X = $imgX; Y = $imgY }
            if ($script:calibPts.Count -ge 2) {
                $px = Get-PxDistance $script:calibPts[0] $script:calibPts[1]
                if ($px -lt 3) {
                    $script:calibPts = @()
                    $status.Text = 'สองจุดใกล้กันเกินไป — คลิกเส้นตารางสองเส้นใหม่อีกครั้ง'
                } else {
                    $script:mPerPx = [double]$numMeters.Value / $px
                    $script:calibrating = $false
                    Update-Status
                }
            } else {
                Update-Status
            }
        }
        else {
            $script:markers += [PSCustomObject]@{ X = $imgX; Y = $imgY }
            Update-Status
        }
    }
    elseif ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
        $nearestIndex = -1
        $nearestDistance = [double]::MaxValue
        for ($i = 0; $i -lt $script:markers.Count; $i++) {
            $x = $view.Left + ($script:markers[$i].X * $view.Scale)
            $y = $view.Top + ($script:markers[$i].Y * $view.Scale)
            $distance = [Math]::Sqrt((($eventArgs.X - $x) * ($eventArgs.X - $x)) + (($eventArgs.Y - $y) * ($eventArgs.Y - $y)))
            if ($distance -lt $nearestDistance) {
                $nearestIndex = $i
                $nearestDistance = $distance
            }
        }
        if ($nearestIndex -ge 0 -and $nearestDistance -le 30) {
            $list = [System.Collections.ArrayList]@($script:markers)
            $list.RemoveAt($nearestIndex)
            $script:markers = @($list)
            Update-Status
        }
    }
    Update-Controls
    $picture.Invalidate()
})

$btnCapture.add_Click({ Capture-Desktop })
$btnMinimize.add_Click({ $form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized })
$btnCalib.add_Click({ Start-Calibration })
$btnClear.add_Click({
    $script:markers = @()
    Update-Controls
    Update-Status
    $picture.Invalidate()
})

$btnSave.add_Click({
    if ($null -eq $script:shot) { return }
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Filter = 'PNG image (*.png)|*.png'
    $dialog.FileName = "MapSnap_$(Get-Date -Format 'yyyyMMdd_HHmmss').png"
    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $output = New-Object System.Drawing.Bitmap($script:shot.Width, $script:shot.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($output)
    try {
        $graphics.DrawImageUnscaled($script:shot, 0, 0)
        Draw-Annotations -Graphics $graphics -OffsetX 0 -OffsetY 0 -Scale 1
        $output.Save($dialog.FileName, [System.Drawing.Imaging.ImageFormat]::Png)
        $status.Text = "บันทึกไฟล์แล้ว: $($dialog.FileName)"
    }
    finally {
        $graphics.Dispose()
        $output.Dispose()
    }
})

$form.add_KeyDown({
    param($sender, $eventArgs)
    if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::F8) {
        Capture-Desktop
        $eventArgs.SuppressKeyPress = $true
    }
    elseif ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::K) {
        Start-Calibration
    }
    elseif ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Delete -and $script:markers.Count -gt 0) {
        $script:markers = @($script:markers | Select-Object -First ($script:markers.Count - 1))
        Update-Controls
        Update-Status
        $picture.Invalidate()
    }
    elseif ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::C) {
        $script:markers = @()
        Update-Controls
        Update-Status
        $picture.Invalidate()
    }
})

try {
    $script:hotkey = New-Object MapSnap.Native.HotKeyWindow
    $script:hotkey.add_Pressed({ Capture-Desktop })
}
catch {
    $status.Text = 'ลงทะเบียนปุ่ม F8 ไม่ได้ (อาจถูกโปรแกรมอื่นใช้) — ใช้ปุ่ม "จับภาพ" ได้'
}

$form.add_FormClosing({
    if ($null -ne $script:hotkey) { $script:hotkey.Dispose() }
    if ($null -ne $script:shot) { $script:shot.Dispose() }
})

[System.Windows.Forms.Application]::Run($form)
