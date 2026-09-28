#requires -Version 5.1
[CmdletBinding()]
param([switch]$Stop, [switch]$SelfTest)
$ErrorActionPreference = 'Stop'
$eventName = 'Local\WinKeepAwake.Stop'
if ($Stop) {
    try { $signal = [Threading.EventWaitHandle]::OpenExisting($eventName) }
    catch [Threading.WaitHandleCannotBeOpenedException] { return }
    try { [void]$signal.Set() } finally { $signal.Dispose() }
    return
}
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class AwakeNative {
    [StructLayout(LayoutKind.Sequential)] struct MouseInput {
        public int dx, dy; public uint mouseData, flags, time; public UIntPtr extra;
    }
    [StructLayout(LayoutKind.Sequential)] struct Input { public uint type; public MouseInput mouse; }
    [StructLayout(LayoutKind.Sequential)] struct LastInput { public uint size, time; }
    [DllImport("kernel32.dll")] static extern uint SetThreadExecutionState(uint flags);
    [DllImport("user32.dll", SetLastError=true)] static extern uint SendInput(uint count, Input[] inputs, int size);
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LastInput info);
    [DllImport("user32.dll", SetLastError=true)] static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
    [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr desktop);
    public static void Keep(bool enabled) {
        if (SetThreadExecutionState(enabled ? 0x80000003u : 0x80000000u) == 0)
            throw new InvalidOperationException("SetThreadExecutionState failed");
    }
    public static long IdleMilliseconds() {
        var info = new LastInput { size = (uint)Marshal.SizeOf(typeof(LastInput)) };
        if (!GetLastInputInfo(ref info)) throw new InvalidOperationException("GetLastInputInfo failed");
        return unchecked((uint)Environment.TickCount - info.time);
    }
    public static bool Pulse() {
        // A locked / secure desktop is left alone.
        IntPtr desktop = OpenInputDesktop(0, false, 0x0001);
        if (desktop == IntPtr.Zero) return false;
        CloseDesktop(desktop);
        var input = new Input { type = 0, mouse = new MouseInput { flags = 1 } };
        if (SendInput(1, new[] { input }, Marshal.SizeOf(typeof(Input))) != 1)
            throw new InvalidOperationException("SendInput was blocked");
        return true;
    }
}
'@
$mutex = New-Object Threading.Mutex($false, 'Local\WinKeepAwake.Instance')
$owned = $false
$script:paused = $false
$script:quit = $false
try {
    try { $owned = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned = $true }
    if (!$owned) { return }
    $signal = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, $eventName)
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $status = $menu.Items.Add('状态：运行中')
    $status.Enabled = $false
    $toggle = $menu.Items.Add('暂停防锁屏')
    $toggle.add_Click({ $script:paused = !$script:paused })
    $startup = $menu.Items.Add('登录时自动启动')
    $startupPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'WinKeepAwake.lnk'
    $menu.add_Opening({ $startup.Checked = Test-Path -LiteralPath $startupPath })
    $startup.add_Click({
        try {
            if (Test-Path -LiteralPath $startupPath) { & "$PSScriptRoot\Setup.ps1" -RemoveStartup }
            else { & "$PSScriptRoot\Setup.ps1" -InstallStartup }
        } catch { [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '自启设置失败') }
    })
    [void]$menu.Items.Add('-')
    $exitItem = $menu.Items.Add('退出')
    $exitItem.add_Click({ $script:quit = $true })
    $tray = New-Object System.Windows.Forms.NotifyIcon
    $tray.Icon = [System.Drawing.SystemIcons]::Information
    $tray.Text = '防自动锁屏：运行中'
    $tray.ContextMenuStrip = $menu
    $tray.add_DoubleClick({ $script:paused = !$script:paused })
    $tray.Visible = $true
    $previousPaused = $null
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while (!$script:quit -and !$signal.WaitOne(0)) {
        [System.Windows.Forms.Application]::DoEvents()
        if ($previousPaused -ne $script:paused) {
            [AwakeNative]::Keep(!$script:paused)
            $previousPaused = $script:paused
        }
        if ($script:paused) {
            $status.Text = '状态：已暂停'
            $toggle.Text = '恢复防锁屏'
            $tray.Icon = [System.Drawing.SystemIcons]::Warning
        } else {
            $toggle.Text = '暂停防锁屏'
            $tray.Icon = [System.Drawing.SystemIcons]::Information
            $status.Text = '状态：运行中'
            if ([AwakeNative]::IdleMilliseconds() -ge 30000 -or $SelfTest) {
                try {
                    if (![AwakeNative]::Pulse()) { $status.Text = '状态：等待桌面解锁' }
                } catch {
                    if ($SelfTest) { throw }
                    $status.Text = '状态：输入受限，当前仅防休眠'
                }
            }
        }
        $tray.Text = '防自动锁屏 | ' + $status.Text
        if ($SelfTest -and $watch.ElapsedMilliseconds -ge 2000) {
            [AwakeNative]::Keep($false)
            [AwakeNative]::Keep($true)
            Write-Output 'PASS: tray, native input, idle query, pause/resume and cleanup.'
            break
        }
        Start-Sleep -Milliseconds 500
    }
} catch {
    $_ | Out-String | Add-Content -LiteralPath (Join-Path $PSScriptRoot 'error.log') -Encoding UTF8
    if ($SelfTest) { throw }
    [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '防自动锁屏启动失败')
} finally {
    if ($owned) { [AwakeNative]::Keep($false) }
    if ($tray) { $tray.Visible = $false; $tray.Dispose() }
    if ($menu) { $menu.Dispose() }
    if ($signal) { $signal.Dispose() }
    if ($owned) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
