# snap_sequence.ps1 - launch geowars_windows.exe in --test-stage mode and run scripted
# screenshot sequences. Each scenario is a list of (action, capture) steps; output goes to
# screenshots/seq/<scenario>/<frame>.png.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools/snap_sequence.ps1
#   powershell -ExecutionPolicy Bypass -File tools/snap_sequence.ps1 -Only idle,lmb
#
# Scenarios:
#   idle          baseline (empty arena, player at centre)
#   lmb           single LMB click, capture launch + flight frames
#   rmb           single RMB tap (current ammo system) + later release
#   grunt         spawn one grunt, watch approach
#   slowboy       spawn one slowboy through windup/charge
#   splitter      spawn one splitter
#   sniper        spawn one sniper through aim
#   disruptor     spawn one disruptor
#   boss          spawn the boss
#   silver_grunt  shift+1 -> silver grunt
#   gold_grunt    ctrl+1  -> gold grunt

param(
    [string]$Exe = "$PSScriptRoot/../geowars_windows.exe",
    [string]$OutRoot = "$PSScriptRoot/../screenshots/seq",
    [int]$BootSeconds = 3,
    [string]$WindowTitle = "GeoWars",
    [string[]]$Only = @()
)

# Allow callers to pass `-Only idle,grunt` from a shell that doesn't expand the comma into
# separate args (most shells outside PowerShell). Split any element that contains a comma.
if ($Only.Count -eq 1 -and $Only[0] -match ',') {
    $Only = $Only[0] -split ','
}

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# C# helper. Adds mouse-input + tap-key on top of snap.ps1's window-capture machinery.
$src = @"
using System;
using System.Runtime.InteropServices;
using System.Drawing;
using System.Drawing.Imaging;

public static class SeqSnap {
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdcBlt, uint nFlags);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern short VkKeyScan(char ch);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref POINT lpPoint);
    [DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] public struct HARDWAREINPUT { public uint uMsg; public ushort wParamL; public ushort wParamH; }
    [StructLayout(LayoutKind.Explicit)] public struct INPUTUNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; [FieldOffset(0)] public HARDWAREINPUT hi; }
    [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public INPUTUNION u; }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }

    public const uint INPUT_KEYBOARD = 1;
    public const uint INPUT_MOUSE    = 0;
    public const uint KEYEVENTF_KEYUP = 0x0002;
    public const uint MOUSEEVENTF_LEFTDOWN  = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP    = 0x0004;
    public const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    public const uint MOUSEEVENTF_RIGHTUP   = 0x0010;

    public static void KeyDown(ushort vkCode) {
        var inp = new INPUT { type = INPUT_KEYBOARD };
        inp.u.ki = new KEYBDINPUT { wVk = vkCode };
        SendInput(1, new INPUT[] { inp }, Marshal.SizeOf(typeof(INPUT)));
    }
    public static void KeyUp(ushort vkCode) {
        var inp = new INPUT { type = INPUT_KEYBOARD };
        inp.u.ki = new KEYBDINPUT { wVk = vkCode, dwFlags = KEYEVENTF_KEYUP };
        SendInput(1, new INPUT[] { inp }, Marshal.SizeOf(typeof(INPUT)));
    }
    public static ushort VkFromChar(char ch) { return (ushort)(VkKeyScan(ch) & 0xFF); }

    public static void MouseDown(uint button) {
        var inp = new INPUT { type = INPUT_MOUSE };
        inp.u.mi = new MOUSEINPUT { dwFlags = button };
        SendInput(1, new INPUT[] { inp }, Marshal.SizeOf(typeof(INPUT)));
    }
    public static void MouseUp(uint button) {
        var inp = new INPUT { type = INPUT_MOUSE };
        inp.u.mi = new MOUSEINPUT { dwFlags = button };
        SendInput(1, new INPUT[] { inp }, Marshal.SizeOf(typeof(INPUT)));
    }

    public static IntPtr FindByTitleSubstring(string fragment) {
        IntPtr found = IntPtr.Zero;
        foreach (var p in System.Diagnostics.Process.GetProcesses()) {
            try {
                if (p.MainWindowHandle != IntPtr.Zero && p.MainWindowTitle != null && p.MainWindowTitle.IndexOf(fragment, StringComparison.OrdinalIgnoreCase) >= 0) {
                    found = p.MainWindowHandle;
                    break;
                }
            } catch {}
        }
        return found;
    }

    public static Bitmap CaptureWindowPrint(IntPtr hwnd) {
        RECT r;
        if (!GetWindowRect(hwnd, out r)) return null;
        int w = r.Right - r.Left;
        int h = r.Bottom - r.Top;
        if (w <= 0 || h <= 0) return null;
        var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bmp)) {
            IntPtr hdc = g.GetHdc();
            try { PrintWindow(hwnd, hdc, 2u); } finally { g.ReleaseHdc(hdc); }
        }
        return bmp;
    }

    public static Bitmap CaptureWindowFromScreen(IntPtr hwnd) {
        RECT r;
        if (!GetWindowRect(hwnd, out r)) return null;
        int w = r.Right - r.Left;
        int h = r.Bottom - r.Top;
        if (w <= 0 || h <= 0) return null;
        var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bmp)) {
            g.CopyFromScreen(r.Left, r.Top, 0, 0, new Size(w, h), CopyPixelOperation.SourceCopy);
        }
        return bmp;
    }

    public static void CenterCursor(IntPtr hwnd) {
        RECT r;
        if (!GetClientRect(hwnd, out r)) return;
        POINT p = new POINT { X = (r.Right - r.Left) / 2, Y = (r.Bottom - r.Top) / 2 };
        ClientToScreen(hwnd, ref p);
        SetCursorPos(p.X, p.Y);
    }

    // Place the cursor at a normalized client-relative offset (0..1 in each axis).
    // Used to put the mouse to the right of the player so LMB shoots in a known direction.
    public static void CursorAt(IntPtr hwnd, double normX, double normY) {
        RECT r;
        if (!GetClientRect(hwnd, out r)) return;
        POINT p = new POINT { X = (int)((r.Right - r.Left) * normX), Y = (int)((r.Bottom - r.Top) * normY) };
        ClientToScreen(hwnd, ref p);
        SetCursorPos(p.X, p.Y);
    }
}
"@
Add-Type -TypeDefinition $src -ReferencedAssemblies "System.Drawing","System.Windows.Forms"

if (-not (Test-Path $Exe)) { Write-Error "Game executable not found at $Exe -- build first via build.bat"; exit 1 }
if (-not (Test-Path $OutRoot)) { New-Item -ItemType Directory -Path $OutRoot | Out-Null }

# Kill stale instance and launch fresh with --test-stage.
Get-Process -Name "geowars_windows" -ErrorAction SilentlyContinue | ForEach-Object { $_ | Stop-Process -Force }
Start-Sleep -Milliseconds 200

Write-Host "Launching $Exe --test-stage ..."
$proc = Start-Process -FilePath $Exe -ArgumentList @('--test-stage') -PassThru
Start-Sleep -Seconds $BootSeconds

$hwnd = [IntPtr]::Zero
try { $hwnd = $proc.MainWindowHandle } catch {}
if ($hwnd -eq [IntPtr]::Zero) { $hwnd = [SeqSnap]::FindByTitleSubstring($WindowTitle) }
if ($hwnd -eq [IntPtr]::Zero) {
    Write-Warning "Could not locate the GeoWars window. Killing process and exiting."
    try { $proc | Stop-Process -Force } catch {}
    exit 2
}

[void][SeqSnap]::ShowWindow($hwnd, 9)
[void][SeqSnap]::SetForegroundWindow($hwnd)
Start-Sleep -Milliseconds 300

# --- Action helpers ----------------------------------------------------------
$global:Hwnd = $hwnd
$global:CurrentDir = ""
$global:FrameIndex = 0

function Wait-Ms { param([int]$ms) Start-Sleep -Milliseconds $ms }

function Tap-Key { param([char]$ch, [int]$holdMs = 30)
    $vk = [SeqSnap]::VkFromChar($ch)
    [SeqSnap]::KeyDown($vk); Wait-Ms $holdMs; [SeqSnap]::KeyUp($vk)
}
# Hold a modifier (shift / ctrl) while tapping a key, mimicking real input order.
function Tap-WithModifier { param([uint16]$modVk, [char]$ch, [int]$holdMs = 30)
    [SeqSnap]::KeyDown($modVk)
    Wait-Ms 20
    Tap-Key $ch $holdMs
    Wait-Ms 20
    [SeqSnap]::KeyUp($modVk)
}
function Click-Mouse { param([string]$button)
    if ($button -eq 'Left') {
        [SeqSnap]::MouseDown([SeqSnap]::MOUSEEVENTF_LEFTDOWN); Wait-Ms 30
        [SeqSnap]::MouseUp([SeqSnap]::MOUSEEVENTF_LEFTUP)
    } else {
        [SeqSnap]::MouseDown([SeqSnap]::MOUSEEVENTF_RIGHTDOWN); Wait-Ms 30
        [SeqSnap]::MouseUp([SeqSnap]::MOUSEEVENTF_RIGHTUP)
    }
}
function MouseDown-Right { [SeqSnap]::MouseDown([SeqSnap]::MOUSEEVENTF_RIGHTDOWN) }
function MouseUp-Right   { [SeqSnap]::MouseUp([SeqSnap]::MOUSEEVENTF_RIGHTUP) }

function Reset-Arena { Tap-Key 'R'; Wait-Ms 100 }

function Snap-Frame { param([string]$label)
    $name = "{0:D2}_{1}.png" -f $global:FrameIndex, $label
    $path = Join-Path $global:CurrentDir $name
    $bmp = [SeqSnap]::CaptureWindowPrint($global:Hwnd)
    if ($bmp -ne $null) {
        $sample = $bmp.GetPixel([Math]::Min(50, $bmp.Width - 1), [Math]::Min(50, $bmp.Height - 1))
        if ($sample.R -eq 0 -and $sample.G -eq 0 -and $sample.B -eq 0) {
            $bmp.Dispose()
            $bmp = [SeqSnap]::CaptureWindowFromScreen($global:Hwnd)
        }
    }
    if ($bmp -ne $null) {
        $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        Write-Host "  + $name"
    } else {
        Write-Warning "  capture failed for $name"
    }
    $global:FrameIndex += 1
}

function Begin-Scenario { param([string]$name)
    $global:CurrentDir = Join-Path $OutRoot $name
    if (Test-Path $global:CurrentDir) { Remove-Item -Recurse -Force $global:CurrentDir }
    New-Item -ItemType Directory -Path $global:CurrentDir | Out-Null
    $global:FrameIndex = 0
    Write-Host "[$name]"
}

# --- Scenario definitions ---------------------------------------------------
# Each scenario assumes the arena was reset just before it runs.
[uint16]$VK_SHIFT = 0x10
[uint16]$VK_CTRL  = 0x11

$scenarios = [ordered]@{
    "idle" = {
        Snap-Frame "baseline"
    }
    "lmb" = {
        # Cursor to right of centre so projectile flies right.
        [SeqSnap]::CursorAt($global:Hwnd, 0.65, 0.5)
        Wait-Ms 100
        Snap-Frame "before"
        Click-Mouse "Left"
        Snap-Frame "t0"
        Wait-Ms 100; Snap-Frame "t100ms"
        Wait-Ms 200; Snap-Frame "t300ms"
        Wait-Ms 300; Snap-Frame "t600ms"
        Wait-Ms 400; Snap-Frame "t1000ms"
    }
    "rmb" = {
        # Aim slightly off-centre so the swirl direction is consistent.
        [SeqSnap]::CursorAt($global:Hwnd, 0.6, 0.5)
        Wait-Ms 100
        Snap-Frame "charge_empty"
        Wait-Ms 5000;  Snap-Frame "charge_50pct"   # ~5s @ 10%/s
        Wait-Ms 5000;  Snap-Frame "charge_100pct"  # full charge — beam ready
        Wait-Ms 5000;  Snap-Frame "charge_150pct"  # overcharge midway
        Wait-Ms 5000;  Snap-Frame "charge_200pct"  # capped
        Click-Mouse "Right"
        Snap-Frame "fired_t0"
        Wait-Ms 200; Snap-Frame "fired_t200ms"
        Wait-Ms 400; Snap-Frame "fired_t600ms"
        Wait-Ms 1000; Snap-Frame "fired_t1600ms"
    }
    "grunt"        = { Tap-Key '1'; Snap-Frame "t0"; Wait-Ms 500; Snap-Frame "t500ms"; Wait-Ms 1000; Snap-Frame "t1500ms"; Wait-Ms 1500; Snap-Frame "t3s" }
    "slowboy"      = { Tap-Key '2'; Snap-Frame "t0"; Wait-Ms 800; Snap-Frame "t800ms"; Wait-Ms 1200; Snap-Frame "t2s"; Wait-Ms 1500; Snap-Frame "t3500ms"; Wait-Ms 2000; Snap-Frame "t5500ms" }
    "splitter"     = { Tap-Key '3'; Snap-Frame "t0"; Wait-Ms 600; Snap-Frame "t600ms"; Wait-Ms 1400; Snap-Frame "t2s" }
    "sniper"       = { Tap-Key '4'; Snap-Frame "t0"; Wait-Ms 500; Snap-Frame "t500ms"; Wait-Ms 1000; Snap-Frame "t1500ms"; Wait-Ms 1000; Snap-Frame "t2500ms" }
    "disruptor"    = { Tap-Key '5'; Snap-Frame "t0"; Wait-Ms 500; Snap-Frame "t500ms"; Wait-Ms 1000; Snap-Frame "t1500ms" }
    "boss"         = { Tap-Key '6'; Snap-Frame "t0"; Wait-Ms 1000; Snap-Frame "t1s"; Wait-Ms 2000; Snap-Frame "t3s"; Wait-Ms 2000; Snap-Frame "t5s" }
    "silver_grunt" = { Tap-WithModifier $VK_SHIFT '1'; Snap-Frame "t0"; Wait-Ms 500; Snap-Frame "t500ms"; Wait-Ms 1500; Snap-Frame "t2s" }
    "gold_grunt"   = { Tap-WithModifier $VK_CTRL  '1'; Snap-Frame "t0"; Wait-Ms 500; Snap-Frame "t500ms"; Wait-Ms 1500; Snap-Frame "t2s" }
    # Low-HP screen-feedback scenarios: press digit keys to jump straight to that HP value.
    # Capture at multiple timestamps so the heartbeat pulse is visible across frames.
    "hp3" = { Tap-Key '7'; Wait-Ms 80; Snap-Frame "frame1"; Wait-Ms 200; Snap-Frame "frame2"; Wait-Ms 200; Snap-Frame "frame3" }
    "hp2" = { Tap-Key '8'; Wait-Ms 80; Snap-Frame "frame1"; Wait-Ms 200; Snap-Frame "frame2"; Wait-Ms 200; Snap-Frame "frame3" }
    "hp1" = { Tap-Key '9'; Wait-Ms 80; Snap-Frame "frame1"; Wait-Ms 150; Snap-Frame "frame2"; Wait-Ms 150; Snap-Frame "frame3"; Wait-Ms 150; Snap-Frame "frame4" }
}

# --- Run --------------------------------------------------------------------
foreach ($name in $scenarios.Keys) {
    if ($Only.Count -gt 0 -and -not ($Only -contains $name)) { continue }
    Reset-Arena
    [SeqSnap]::CenterCursor($global:Hwnd)
    Wait-Ms 150
    Begin-Scenario $name
    & $scenarios[$name]
}

# Cleanup
try { $proc | Stop-Process -Force } catch {}
Write-Host "Done. Output -> $OutRoot"
exit 0
