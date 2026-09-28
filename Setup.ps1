#requires -Version 5.1
[CmdletBinding()]
param([switch]$InstallStartup, [switch]$RemoveStartup, [switch]$InstallDesktop)
$ErrorActionPreference = 'Stop'
if ($InstallStartup -and $RemoveStartup) { throw '不能同时添加和移除自启。' }
$startup = Join-Path ([Environment]::GetFolderPath('Startup')) 'WinKeepAwake.lnk'
function Install-Shortcut([string]$Path) {
    $shell = New-Object -ComObject WScript.Shell
    try {
        $link = $shell.CreateShortcut($Path)
        $link.TargetPath = "$env:SystemRoot\System32\wscript.exe"
        $link.Arguments = '//B //Nologo "' + (Join-Path $PSScriptRoot 'Start-Hidden.vbs') + '"'
        $link.WorkingDirectory = $PSScriptRoot
        $link.Description = '防自动锁屏（双击托盘暂停/恢复）'
        $link.IconLocation = "$env:SystemRoot\System32\shell32.dll,44"
        $link.Save()
    } finally {
        if ($link) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($link) }
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
    }
}
if ($RemoveStartup) {
    Remove-Item -LiteralPath $startup -Force -ErrorAction SilentlyContinue
    Write-Host '已移除登录自启，正在运行的托盘仍可手动退出。'
}
if ($InstallStartup) { Install-Shortcut $startup; Write-Host '已启用当前用户登录自启。' }
if ($InstallDesktop) {
    Install-Shortcut (Join-Path ([Environment]::GetFolderPath('Desktop')) '防自动锁屏.lnk')
    Write-Host '已创建桌面快捷方式。'
}
if (!$InstallStartup -and !$RemoveStartup -and !$InstallDesktop) { Write-Host '使用 -InstallStartup 添加自启，-RemoveStartup 移除自启，-InstallDesktop 创建桌面快捷方式。' }
