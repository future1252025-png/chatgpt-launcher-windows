# ChatGPT Launcher for Windows

一个面向普通 Windows 用户的 ChatGPT/Codex 桌面版启动器。它负责可靠启动 Microsoft Store 应用、等待真实窗口出现，并可在应用启动前准备本地运行时。[English README](README.en.md)。

This project is an independent community utility and is not affiliated with or endorsed by OpenAI.

## 特性

- 自动发现当前用户安装的、由 Microsoft Store 签名的 ChatGPT/Codex 应用。
- 使用 AppUserModelID 启动应用，不依赖具体安装版本目录。
- 如果窗口已经存在，恢复并切换到前台。
- 单实例锁，防止重复双击造成并发复制或重复启动。
- 最多三次启动尝试和指数退避，不会持续形成崩溃循环。
- 日志保存在 `%LOCALAPPDATA%\ChatGPTLauncher\Logs`，最多保留 20 份。
- 可选的首次启动运行时修复：只复制已安装、经过 Store 签名的软件包内容，不从网络下载文件。
- 仅在应用未运行时准备运行时，复制到临时目录并验证文件长度后再切换；切换成功后清理旧目录备份。
- 缓存软件包版本、运行时标识和文件数量，减少后续启动时的重复准备。
- 应用已在后台启动时继续等待，不终止或重启已有进程。
- 安装器生成本地图标，应用更新后快捷方式图标不会指向被删除的旧版本目录。
- 不需要管理员权限，不修改注册表，不修改代理配置。

## 系统要求

- 可以安装该桌面应用的 Windows 版本。
- Windows PowerShell 5.1 或更高版本。
- 已为当前用户安装 Microsoft Store 版本的 ChatGPT/Codex 桌面应用。

## 安装

双击 `Install.cmd`，或在项目目录打开 PowerShell：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

默认安装到：

```text
%LOCALAPPDATA%\Programs\ChatGPTLauncher
```

并在桌面和开始菜单创建 `ChatGPT Launcher` 快捷方式。项目源码可以放在任意磁盘或目录。
安装器不会覆盖没有本项目安装标记的非空目录，也不会安装到源码目录本身。

可选参数：

```powershell
.\Install.ps1 -NoDesktopShortcut
.\Install.ps1 -NoStartMenuShortcut
.\Install.ps1 -LaunchAfterInstall
.\Install.ps1 -InstallDirectory "D:\Apps\ChatGPTLauncher"
.\Install.ps1 -DesktopShortcutName "ChatGPT 启动器"
.\Install.ps1 -DesktopShortcutName "ChatGPT 启动器" -ReplaceExistingShortcut
```

## 便携运行

不安装也可以直接双击：

```text
Launch-ChatGPT.cmd
```

或使用 PowerShell：

```powershell
.\Launch-ChatGPT.ps1
.\Launch-ChatGPT.ps1 -WaitSeconds 300
.\Launch-ChatGPT.ps1 -RuntimeRepair Never
.\Launch-ChatGPT.ps1 -Diagnostics
```

`RuntimeRepair Auto` 是默认值，默认等待窗口的期限为 1200 秒。安装包包含对应的 `cua_node` 运行时且应用尚未运行时，启动器会在启动前检查缓存并按需准备运行时。若应用已经在后台启动，则继续等待其自行完成，不打断正在进行的运行时复制。使用 `-RuntimeRepair Never` 可跳过启动器的运行时准备。

## 安全设计

需要准备运行时时，启动器按以下顺序执行：

1. 根据软件包清单和核心二进制文件的 SHA-256 计算运行时目录标识。
2. 确认应用未运行，从已安装的 Store 软件包复制到运行时根目录中的临时目录。
3. 验证所有来源文件在临时目录中都存在且长度一致。
4. 再次确认应用未运行，将旧目录重命名为备份，并将临时目录切换到最终位置。
5. 再次验证文件长度，记录软件包版本、运行时标识和文件数量，再清理旧目录备份。
6. 启动应用并等待窗口出现；准备失败时记录警告，让官方应用自行准备运行时。

启动器不会删除 ChatGPT 用户数据，也不会下载或执行第三方二进制文件。

## 日志与诊断

运行：

```powershell
.\Launch-ChatGPT.ps1 -Diagnostics
.\tests\Smoke-Test.ps1
```

日志目录：

```text
%LOCALAPPDATA%\ChatGPTLauncher\Logs
```

退出码：

- `0`：窗口已出现，或诊断通过。
- `1`：安装、启动、验证或诊断失败。
- `3`：另一个启动器实例正在运行。

## 卸载

双击 `Uninstall.cmd`，或在项目目录、安装目录运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1
```

添加 `-RemoveLogs` 可以同时删除启动器日志。卸载器不会删除 ChatGPT 应用、账号数据或应用运行时。
如果使用了自定义安装目录，可直接从该目录运行 `Uninstall.cmd`；若从源码目录运行卸载器，请传入相同的 `-InstallDirectory`。

## 已知限制

- 首次启动加速依赖当前桌面应用使用 `cua_node` 打包布局；如果未来应用结构改变，启动器会让官方应用自行继续启动，并记录警告。
- Windows 可能拒绝第三方程序强制抢占前台焦点；这时窗口仍会正常打开，但任务栏可能只会闪烁。
- 项目目前识别 Microsoft Store 的 `OpenAI.Codex` 包，不处理未知来源的便携版应用。
