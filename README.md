# ChatGPT Launcher for Windows

一个面向普通 Windows 用户的 ChatGPT/Codex 桌面版启动器。它负责可靠启动 Microsoft Store 应用、等待真实窗口出现，并在首次启动的本地运行时准备阶段安全地提供加速恢复。[English README](README.en.md)。

This project is an independent community utility and is not affiliated with or endorsed by OpenAI.

## 特性

- 自动发现当前用户安装的、由 Microsoft Store 签名的 ChatGPT/Codex 应用。
- 使用 AppUserModelID 启动应用，不依赖具体安装版本目录。
- 如果窗口已经存在，恢复并切换到前台。
- 单实例锁，防止重复双击造成并发复制或重复启动。
- 最多三次启动尝试和指数退避，不会持续形成崩溃循环。
- 日志保存在 `%LOCALAPPDATA%\ChatGPTLauncher\Logs`，最多保留 20 份。
- 可选的首次启动运行时修复：只复制已安装、经过 Store 签名的软件包内容，不从网络下载文件。
- 运行时先复制到临时目录，验证文件和核心哈希后才停止应用并切换；旧的不完整目录会被保留为备份。
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

`RuntimeRepair Auto` 是默认值，最长等待 600 秒。只有同时满足以下条件时才会介入：应用超过 15 秒没有窗口、进程仍存在、检测到当前进程启动后创建的 `.staging-*` 目录、安装包中存在对应的运行时来源。

## 安全设计

运行时修复按以下顺序执行：

1. 从当前已安装的 Store 软件包复制到新的临时目录。
2. 验证所有来源文件都存在且长度一致。
3. 对 `node.exe` 和 `node_repl.exe` 做 SHA-256 对比。
4. 只停止路径属于所选 Store 软件包的 `ChatGPT.exe` 进程。
5. 将旧的不完整目录重命名为可恢复备份。
6. 将验证后的目录移动到最终位置并再次验证。

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
