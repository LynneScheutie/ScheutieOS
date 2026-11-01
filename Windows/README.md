# ScheutieOS for Windows

DeepSeek 网页的独立窗口客户端（WinForms + WebView2），与 macOS 版同版本号 **8.4.2**。

交付形态：**自解压安装 EXE** —— 双击下载得到的 `ScheutieOS-8.4.2-Setup.exe` 后，程序把自己「解压」到 `%LOCALAPPDATA%\ScheutieOS`、创建快捷方式、注册卸载信息，然后自动启动。安装完成后，双击桌面 / 开始菜单里的 ScheutieOS 即可直接运行。

## 快速开始

| 步骤 | 说明 |
| --- | --- |
| 1. 构建 | 在任意 Windows 10+ 机器上运行 `build.ps1`（需要 PowerShell 5.1+；没有 .NET SDK 8 会自动安装，优先走 winget，无管理员权限也能装到项目目录） |
| 2. 得到产物 | `build\ScheutieOS-8.4.2-Setup.exe`（约 90–150 MB，内置 .NET 运行时，安装后不需要任何依赖） |
| 3. 安装 | 拷到 Windows 电脑，双击 → 点「安装」→ 应用自动启动 |
| 4. 日常使用 | 桌面 / 开始菜单的 ScheutieOS 快捷方式 |

> 构建产物体积较大是因为选择了**自包含单文件发布**：exe 里带着整个 .NET 运行时，装完即用，不要求用户预装任何东西。

## 命令行

| 命令 | 作用 |
| --- | --- |
| `ScheutieOS-Setup.exe`（无参数，且不在安装目录） | 显示安装窗口 |
| `--install --silent` | 静默安装（默认创建桌面 + 开始菜单快捷方式）并启动 |
| `--app` | 跳过安装，直接当应用运行 |
| `--diag` | 把环境诊断写入日志并退出 |
| `--uninstall` | 启动卸载流程（也可从「帮助」菜单或系统「应用和功能」进入） |

## 功能清单（与 macOS 版对照）

| 功能 | 说明 |
| --- | --- |
| 独立窗口 | WebView2 加载 chat.deepseek.com，无浏览器界面；登录状态持久保存（数据在 `%APPDATA%\ScheutieOS\WebView2`） |
| 窗口行为 | 左上角 × 只收起窗口到通知区；**Ctrl+Q**（或「文件 → 退出」）才是完全退出；再次双击快捷方式会唤醒已隐藏的窗口（单实例） |
| 外观 | 增强 → 外观：跟随系统 / 强制暗色 / 强制亮色 |
| 浏览器标识 | 增强 → 浏览器标识：5 个预设 UA + 自定义；修改后自动重载 |
| 页面样式 | 隐藏滚动条、禁用动画与过渡、自定义 CSS（CSP 免疫注入）、重新应用；均持久化 |
| 对话导出 | 复制对话为 Markdown（Ctrl+Shift+C）、导出为 .md 文件（Ctrl+Shift+S）、复制全文纯文本、打印 / 存为 PDF（Ctrl+P） |
| 查找 | Ctrl+F，页面内查找（上一个 / 下一个） |
| 缩放 | 菜单「显示 → 放大 / 缩小 / 实际大小」，**无快捷键**（和 macOS 版一致，防误触）；Ctrl+滚轮 / 双指缩放也已禁用 |
| 下载 | 自动存到「下载」文件夹 |
| 外链 | 非 deepseek.com 的链接与新窗口请求交给系统默认浏览器 |
| 全屏 | F11 |
| 关于窗口 | 手绘渐变卡片：图标、版本徽章（8.4.2 build 842）、开发者 Lynne Scheutie & Wanchen Qian、A quick launcher for DeepSeek |
| 卸载 | 帮助 → 卸载；已注册到系统「应用和功能」，可选是否保留登录数据 |

## 目录与文件

| 路径 | 内容 |
| --- | --- |
| `%LOCALAPPDATA%\ScheutieOS\` | 安装目录（就一个 exe） |
| `%APPDATA%\ScheutieOS\settings.json` | 所有增强设置、窗口位置 |
| `%APPDATA%\ScheutieOS\WebView2\` | 登录数据 / 网页存储 |
| `%APPDATA%\ScheutieOS\ScheutieOS.log` | 诊断日志（帮助菜单可一键打开） |

## 项目结构

| 文件 | 职责 |
| --- | --- |
| `src/Program.cs` | 入口与模式分发（app / installer / uninstall / diag）+ 单实例 |
| `src/MainForm.cs` | 主窗口：菜单、WebView2、增强功能、托盘、Ctrl+Q |
| `src/InjectedJs.cs` | 注入页面的 JS 运行时（CSS 注入 + Markdown 导出，与 macOS 版同源） |
| `src/Prefs.cs` | JSON 设置持久化 |
| `src/AboutForm.cs` | 手绘关于窗口 |
| `src/InstallerForm.cs` / `Installer.cs` | 安装窗口与安装步骤 |
| `src/Uninstaller.cs` | 两阶段卸载（先把自身复制到 TEMP 再删自己） |
| `src/Shortcuts.cs` | Shell COM 创建 .lnk + 注册卸载表项 |
| `assets/AppIcon.ico` | 多尺寸图标（16–256px，由 `tools/make_ico.py` 生成） |
| `build.ps1` | 一键构建 |

## 已知限制

- 只能在 Windows 上编译运行；本仓库是在 macOS 上开发的，**产物未在真机验证**，首次构建如有报错把日志发回来即可。
- 「解压安装」指单文件发布在首次运行时解出原生依赖，并把自身复制到安装目录；不是 7-Zip / NSIS 那种压缩包外壳，但用户体验一致：双击 → 安装 → 运行。
- WebView2 运行时依赖 Edge（Win11 / 新版 Win10 自带）；缺失时启动会给出官方下载链接。
