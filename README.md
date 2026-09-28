# Windows 防自动锁屏

Windows 10/11 + Windows PowerShell 5.1，无需管理员权限或第三方模块。

双击 `Start-Hidden.vbs` 启动，仅显示托盘图标。右键可暂停/恢复、切换登录自启、退出；双击图标也可暂停/恢复。重复启动不会出现多个实例。

运行时保持屏幕和系统唤醒，每 0.5 秒检查一次空闲时间，空闲达到 30 秒后发送无位移鼠标事件，不点击、不输入字符。暂停或退出后释放唤醒请求，恢复系统原有空闲行为；暂停状态不跨重启保存。

手动 Win+L 仍有效，脚本不会解锁桌面。组织强制锁屏策略、动态锁或禁止模拟输入的环境可能仍会锁屏；本工具不能保证阻止这些锁屏。运行期间屏幕保持点亮，会增加耗电。

在此目录打开 PowerShell：

```powershell
# 设置当前用户登录自启（开机登录后运行）并创建桌面入口
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 -InstallStartup -InstallDesktop
# 取消自启
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 -RemoveStartup
# 停止当前实例，也可从托盘退出
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\WinKeepAwake.ps1 -Stop
# 原生接口和托盘冒烟检查，请先退出当前实例
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File .\WinKeepAwake.ps1 -SelfTest
```

保留目录位置；移动后重新安装快捷方式。启动错误写入 `error.log`。卸载时先取消自启、退出，再删除目录及桌面快捷方式。

实现依据：[SetThreadExecutionState](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-setthreadexecutionstate) 用于防休眠和熄屏，但不能单独阻止屏保；[SendInput](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput) 用于生成鼠标输入，受桌面和权限限制。
