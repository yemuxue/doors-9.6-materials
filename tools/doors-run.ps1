# doors-run.ps1 - run a DXL file in the already-running DOORS client via COM.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\doors-run.ps1 -DxlFile .\script.dxl
#
# Why this wrapper exists:
#   * DOORS.Application.runFile() / runStr() execute DXL inside the running client.
#   * A DXL compile/runtime error pops a MODAL dialog, which blocks the COM call forever.
#   * This script runs the COM call in a background job, clicks the dialog's OK button
#     as soon as it appears, then prints the text of the "DXL output" pane.
#
# Requires: DOORS 9.x client running and logged in to a database (Administrator or a user
# with "Edit DXL" powers).

param(
    [Parameter(Mandatory = $true)][string]$DxlFile,
    [int]$WaitSeconds = 30
)

$ErrorActionPreference = 'Stop'
$DxlFile = (Resolve-Path $DxlFile).Path

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public struct DoorsRect { public int Left, Top, Right, Bottom; }

public class DoorsWin
{
    public delegate bool EnumProc(IntPtr h, IntPtr l);

    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out DoorsRect r);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);

    public static string ClassOf(IntPtr h) { var c = new StringBuilder(256); GetClassName(h, c, 256); return c.ToString(); }
    public static string TitleOf(IntPtr h) { var t = new StringBuilder(512); GetWindowText(h, t, 512); return t.ToString(); }

    public static List<IntPtr> TopWindows(uint pid)
    {
        var list = new List<IntPtr>();
        EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (p == pid) list.Add(h); return true; }, IntPtr.Zero);
        return list;
    }

    public static List<IntPtr> Children(IntPtr parent)
    {
        var list = new List<IntPtr>();
        EnumChildWindows(parent, (h, l) => { list.Add(h); return true; }, IntPtr.Zero);
        return list;
    }

    public static IntPtr FindModal(uint pid)
    {
        foreach (var h in TopWindows(pid))
            if (ClassOf(h) == "#32770" && IsWindowVisible(h)) return h;
        return IntPtr.Zero;
    }

    public static string DialogText(IntPtr dlg)
    {
        var sb = new StringBuilder();
        foreach (var c in Children(dlg))
            if (ClassOf(c) == "Static" && TitleOf(c).Length > 0) sb.AppendLine(TitleOf(c));
        return sb.ToString().Trim();
    }

    public static bool ClickOk(IntPtr dlg)
    {
        IntPtr fallback = IntPtr.Zero;
        foreach (var c in Children(dlg))
        {
            if (ClassOf(c) != "Button") continue;
            string txt = TitleOf(c);
            if (fallback == IntPtr.Zero) fallback = c;
            // \u786E\u5B9A = 确定, \u662F = 是
            if (txt == "OK" || txt == "\u786E\u5B9A" || txt == "\u662F" || txt == "Yes")
            {
                SendMessage(c, 0x00F5, IntPtr.Zero, IntPtr.Zero);
                return true;
            }
        }
        if (fallback != IntPtr.Zero)
        {
            SendMessage(fallback, 0x00F5, IntPtr.Zero, IntPtr.Zero);
            return false;
        }
        SendMessage(dlg, 0x0010, IntPtr.Zero, IntPtr.Zero);
        return false;
    }

    // The DXL Interaction window owns two rich edits: input on top, output below.
    public static IntPtr FindDxlOutput(uint pid)
    {
        IntPtr best = IntPtr.Zero;
        int bestTop = int.MinValue;
        foreach (var h in TopWindows(pid))
        {
            if (ClassOf(h) != "DOORSWindow") continue;
            if (!TitleOf(h).Contains("DXL")) continue;
            foreach (var c in Children(h))
            {
                if (ClassOf(c) != "RICHEDIT50W") continue;
                DoorsRect r; GetWindowRect(c, out r);
                if (r.Top > bestTop) { bestTop = r.Top; best = c; }
            }
        }
        return best;
    }
}
'@

function Get-DoorsPid {
    $p = Get-Process doors -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $p) { throw "DOORS client (doors.exe) is not running." }
    return $p.Id
}

function Read-DxlOutput {
    param([int]$DoorsPid)
    $h = [DoorsWin]::FindDxlOutput([uint32]$DoorsPid)
    if ($h -eq [IntPtr]::Zero) { return "" }
    try {
        $el = [System.Windows.Automation.AutomationElement]::FromHandle($h)
        return $el.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern).DocumentRange.GetText(-1)
    } catch { return "" }
}

$doorsPid = Get-DoorsPid
$before = Read-DxlOutput -DoorsPid $doorsPid

$job = Start-Job -ArgumentList $DxlFile -ScriptBlock {
    param($file)
    $dxl = New-Object -ComObject DOORS.Application
    $dxl.runFile($file)
}

$deadline = (Get-Date).AddSeconds($WaitSeconds)
$dialogs = New-Object System.Collections.ArrayList

while ($job.State -eq 'Running') {
    $dlg = [DoorsWin]::FindModal([uint32]$doorsPid)
    if ($dlg -ne [IntPtr]::Zero) {
        [void]$dialogs.Add([DoorsWin]::DialogText($dlg))
        [DoorsWin]::ClickOk($dlg) | Out-Null
        Start-Sleep -Milliseconds 800
        continue
    }
    if ((Get-Date) -gt $deadline) { Stop-Job $job -ErrorAction SilentlyContinue; break }
    Start-Sleep -Milliseconds 300
}

$state = $job.State
$err = $null
try { Receive-Job $job -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null } catch { }
Remove-Job $job -Force -ErrorAction SilentlyContinue

Start-Sleep -Milliseconds 500
$after = Read-DxlOutput -DoorsPid $doorsPid

Write-Output "=== dialogs dismissed: $($dialogs.Count) ==="
foreach ($d in $dialogs) { Write-Output "  [dialog] $d" }
Write-Output "=== job state: $state ==="
if ($err) { foreach ($e in $err) { Write-Output "  [job error] $($e.ToString())" } }
Write-Output "=== DXL output (new lines) ==="
if ($after.Length -ge $before.Length -and $after.StartsWith($before)) {
    Write-Output $after.Substring($before.Length).Trim()
} else {
    Write-Output $after.Trim()
}
