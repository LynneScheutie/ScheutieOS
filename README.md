# ScheutieOS

把 `chat.deepseek.com` 装进一个独立窗口，顺便补上网页端最缺的一样东西：**把长对话导出来**。

macOS 版 Swift + WKWebView，Windows 版 C# WinForms + WebView2。当前版本 macOS **8.4.2**、Windows **8.4.1**。

## 为什么做这个

网页版能聊，但导不出来。一段聊了几十轮的对话，想留存只有两个办法：截图，或者手动全选复制——后者会把侧边栏、按钮文字、时间戳一起带进来，粘到文档里还得逐行清理。

这个客户端把对话结构化提取出来，三种格式随便挑，并且给了一个网页端没有的统计：这段对话到底多少字、其中中文多少、英文多少。

## 导出

| 方式 | 说明 |
| --- | --- |
| **PDF** | 「打印 / 存储为 PDF…」（⌘P / Ctrl+P），走系统打印管线，排版与屏幕一致，适合归档与打印 |
| **Markdown** | 保留标题、列表、代码块结构，适合再编辑或放进笔记软件 |
| **纯文本** | 只要文字，不要格式 |
| **剪贴板** | 复制全文、复制选中、复制为 Markdown，三种粒度 |

导出前会先剥掉对话容器之外的界面元素，所以粘出来的是干净的对话，不含按钮和侧栏。

## 字数统计

「统计对话字数」给出三个数字：

```
共 12483 字符 · 中文 6821 字 · 英文 912 词
```

中英文分开计——中文按字计、英文按词计，混排内容不会被算成一个笼统的「字符数」。长对话想估算篇幅、判断该不该拆分时有用。

## 阅读增强

- **外观**：跟随系统 / 强制暗色 / 强制亮色，覆盖网页自身的主题判断
- **自定义 CSS**：粘贴自己的样式表，用来调字号、行距、代码块配色。注入方式是 `adoptedStyleSheets` 构造样式表，绕开页面的 Content-Security-Policy——普通的 `<style>` 标签在这里会被直接拦掉
- **自定义 User-Agent**：网页会识别「非浏览器」并降级渲染，靠 UA 覆盖绕过去
- **多标签**：一个窗口开多个会话
- **八种界面语言**：中、英、法、俄、西、阿、日、韩

## 目录

| 路径 | 说明 |
| --- | --- |
| `macOS/src/main.swift` | 主窗口、菜单、标签会话、导出流程（1636 行） |
| `macOS/src/Enhance.swift` | 外观覆盖、CSS 注入、Markdown 导出、字数统计（611 行） |
| `macOS/src/L10n.swift` | 八语言文案表（317 行） |
| `macOS/src/About.swift` | 关于面板与更新检查 |
| `macOS/tests/` | 导出逻辑的样例与测试 |
| `Windows/src/MainForm.cs` | Windows 主窗口（893 行） |
| `Windows/src/InjectedJs.cs` | 注入到页面的增强运行时，从 macOS 版移植 |
| `Windows/src/Installer.cs` 等 | 自解压安装、卸载、快捷方式（约 400 行） |

## 构建

### macOS

需要 Xcode 命令行工具。图标处理与 DMG 排版用 Python：

```bash
cd macOS
pip3 install pillow            # 仅生成图标时需要
./build.sh                     # 产出 build/ScheutieOS.app
./make_dist.sh                 # 产出 dist/*.dmg / .pkg / .zip
```

`make_dist.sh` 排版 DMG 还需要 `mac_alias` 与 `ds_store`：

```bash
pip3 install mac_alias ds_store pillow
```

### Windows

在 Windows 10+ 上，PowerShell 5.1 起：

```powershell
cd Windows
.\build.ps1
```

没有 .NET SDK 8 会自动装（优先走 winget，无管理员权限也能装到项目目录）。产出 `build\ScheutieOS-Setup.exe`，自包含 .NET 运行时，装到别的机器不需要任何依赖。

### 测试

导出与统计的提取逻辑有离线测试，用 jsdom 跑，不联网：

```bash
cd macOS
npm install --prefix tests jsdom
./tests/run.sh
```

## 已知局限

说在前面，省得装了才发现：

- **依赖上游页面结构**。导出和统计都是解析 `chat.deepseek.com` 的 DOM，DeepSeek 改版就可能失效，得跟着改选择器
- **不是官方客户端**。本项目与 DeepSeek 无关，只是把公开网页装进窗口
- **CSP 收紧会影响注入**。目前靠 `adoptedStyleSheets` 绕过，如果对方改成更严格的策略，自定义 CSS 会先失效
- **导出长度受页面渲染限制**。极长的对话如果网页本身虚拟滚动了，没渲染过的部分取不到

## 许可证

MIT，见 [LICENSE](LICENSE)。

© Eisice
