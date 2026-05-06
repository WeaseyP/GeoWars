# snap.ps1 - launch the game, wait, screenshot its window, kill it.
# Usage: powershell -ExecutionPolicy Bypass -File tools/snap.ps1 [-WaitSeconds 3] [-Out screenshots/snap.png]

param(
    [string]$Exe = "$PSScriptRoot/../geowars_windows.exe",
    [string]$Out = "$PSScriptRoot/../screenshots/snap.png",
    [int]$WaitSeconds = 3,
    [string]$WindowTitle = "GeoWars",
    # Hold this character (W/A/S/D, or empty) for HoldSeconds before snapping.
    # Used to drive the player toward the arena boundary for bounce verification.
    [string]$HoldKey = "",
    [double]$HoldSeconds = 0.0
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# C# helper to use PrintWindow (works for hardware-accelerated windows via PW_RENDERFULLCONTENT=2).
$src = @"
using System;
using System.Runtime.InteropServices;
using System.Drawing;
using System.Drawing.Imaging;

public static class Snap {
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdcBlt, uint nFlags);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref POINT lpPoint);
    [DllImport("user32.dll")] public static extern short VkKeyScan(char ch);
    [DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] public struct HARDWAREINPUT { public uint uMsg; public ushort wParamL; public ushort wParamH; }
    [StructLayout(LayoutKind.Explicit)] public struct INPUTUNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; [FieldOffset(0)] public HARDWAREINPUT hi; }
    [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public INPUTUNION u; }

    public const uint INPUT_KEYBOARD = 1;
    public const uint KEYEVENTF_KEYUP = 0x0002;

    public static void HoldKey(IntPtr hwnd, char keyChar, double seconds) {
        short vk = VkKeyScan(keyChar);
        ushort vkCode = (ushort)(vk & 0xFF);

        // Send KEYDOWN once. SendInput injects into the foreground window's input queue
        // — caller must ensure the game window is foreground.
        var down = new INPUT { type = INPUT_KEYBOARD };
        down.u.ki = new KEYBDINPUT { wVk = vkCode };
        SendInput(1, new INPUT[] { down }, Marshal.SizeOf(typeof(INPUT)));

        var sw = System.Diagnostics.Stopwatch.StartNew();
        while (sw.Elapsed.TotalSeconds < seconds) {
            System.Threading.Thread.Sleep(20);
        }

        var up = new INPUT { type = INPUT_KEYBOARD };
        up.u.ki = new KEYBDINPUT { wVk = vkCode, dwFlags = KEYEVENTF_KEYUP };
        SendInput(1, new INPUT[] { up }, Marshal.SizeOf(typeof(INPUT)));
    }

    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }

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

    // Capture the window via PrintWindow with PW_RENDERFULLCONTENT (works for D3D/GL HW-accelerated windows).
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

    // Fallback: capture from screen using the window's bounding rectangle.
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
}
"@

Add-Type -TypeDefinition $src -ReferencedAssemblies "System.Drawing","System.Windows.Forms"

if (-not (Test-Path $Exe)) {
    Write-Error "Game executable not found at $Exe - build first via build.bat"
    exit 1
}

$outDir = Split-Path -Parent $Out
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

# Kill any stale game instance so we get a fresh window.
Get-Process -Name "geowars_windows" -ErrorAction SilentlyContinue | ForEach-Object { $_ | Stop-Process -Force }
Start-Sleep -Milliseconds 200

Write-Host "Launching $Exe ..."
$proc = Start-Process -FilePath $Exe -PassThru
Start-Sleep -Seconds $WaitSeconds

# Find the window. Try by exact handle first, then by title substring.
$hwnd = [IntPtr]::Zero
try { $hwnd = $proc.MainWindowHandle } catch {}
if ($hwnd -eq [IntPtr]::Zero) {
    $hwnd = [Snap]::FindByTitleSubstring($WindowTitle)
}
if ($hwnd -eq [IntPtr]::Zero) {
    Write-Warning "Could not locate the GeoWars window. Killing process and exiting."
    try { $proc | Stop-Process -Force } catch {}
    exit 2
}

[void][Snap]::ShowWindow($hwnd, 9)        # SW_RESTORE
[void][Snap]::SetForegroundWindow($hwnd)
Start-Sleep -Milliseconds 250

# Optionally hold a key (W/A/S/D) to drive the player toward the arena edge.
if ($HoldKey -ne "" -and $HoldSeconds -gt 0.0) {
    Write-Host "Holding key '$HoldKey' for $HoldSeconds seconds..."
    [Snap]::HoldKey($hwnd, [char]$HoldKey.ToUpper()[0], $HoldSeconds)
    Start-Sleep -Milliseconds 100
}

# Try PrintWindow first (hardware-accelerated capture).
$bmp = [Snap]::CaptureWindowPrint($hwnd)

# If the capture is mostly black, fall back to screen capture.
if ($bmp -ne $null) {
    $sample = $bmp.GetPixel([Math]::Min(50, $bmp.Width - 1), [Math]::Min(50, $bmp.Height - 1))
    if ($sample.R -eq 0 -and $sample.G -eq 0 -and $sample.B -eq 0) {
        Write-Host "PrintWindow returned black; falling back to screen capture."
        $bmp.Dispose()
        $bmp = [Snap]::CaptureWindowFromScreen($hwnd)
    }
}

if ($bmp -eq $null) {
    Write-Warning "Capture failed."
    try { $proc | Stop-Process -Force } catch {}
    exit 3
}

$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host "Saved screenshot to $Out"

# Clean up: kill the game.
try { $proc | Stop-Process -Force } catch {}
exit 0
