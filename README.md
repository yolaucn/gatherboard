# 归拢 · Gatherboard

一款原生 macOS 本地项目看板，把散落的任务、备忘、链接和文件归拢到项目里。英文名 Gatherboard。

## 启动

双击 `build/归拢.app`，或双击根目录的 `启动归拢.command`。

首发安装包是 [`website/dist/downloads/归拢-1.0.0-universal.dmg`](website/dist/downloads/归拢-1.0.0-universal.dmg)，适配 Apple Silicon 和 Intel Mac，要求 macOS 13 或以上。双击打开后，把「归拢」拖到旁边的「应用程序」文件夹，复制完成后从 Finder「应用程序」打开。图标已内置，安装包不包含任何个人项目或图片。

DMG 是只读的安装载体，装完可推出或删除；它不保存项目资料。应用从任意位置启动，默认使用同一份用户资料库。

应用为本地临时签名，尚未使用 Developer ID 签名和 Apple 公证；其他 Mac 首次运行可能需要按系统提示在「隐私与安全性」允许打开。正式公开分发需要配置开发者签名与公证。Apple Silicon 版本已本机运行验证；Intel 版本交叉编译并合并，尚未实机验证。

当前原生版本不支持 Windows；Windows 版需要另行实现跨平台界面及文件系统集成。

新电脑首次启动为空资料库，不自动生成截图中的项目或读取浏览器数据。

## 文件存在哪里

默认保存在当前用户的 `~/Library/Application Support/归拢`。这是真实文件目录，不是 App Sandbox 容器。更新或移动应用不会改变默认资料位置，也不会覆盖资料：

```text
~/Library/Application Support/归拢/
  library.json                         # 项目、任务、备忘、链接
  Projects/
    售后体验日--随机标识/
      图片.png                         # 原文件，保持原始格式和字节
      staging太阳码/
        图片.webp
```

菜单「资料库 → 在 Finder 中打开资料目录」可以直接打开；也可以在 Finder 按 ⇧⌘G 输入上面的路径。

菜单「资料库 → 选择其他资料库」可以打开或新建其他位置的资料库。选择后会记住位置，已有资料不会自动搬迁。需要自行搬迁时，先关闭应用，用 Finder 复制整个资料文件夹，再选择新位置。用户指定的自定义资料库会保持原位置。

归拢 1.0.0 是独立的第一版，不读取或迁移其他应用的资料。未启用 App Sandbox；macOS 对桌面、文稿、下载等目录的系统隐私授权仍正常生效。

## 使用

- 左侧新建、切换项目；项目名双击或点击铅笔可重命名，真实文件夹也会改名。
- 任务支持完成状态、截止日期、点击编辑和删除。
- 备忘支持标题、自动保存、富文本与粘贴表格/图片，由原生 NSTextView 编辑。
- 链接支持标题、复制，以及用默认浏览器打开 http/https 地址。
- 「文件」中点击导入或拖入文件/文件夹，会复制原件到当前分类；原来源保持不变。
- 支持粘贴剪贴板图片，也支持从 Finder 复制文件后在文件区粘贴。
- 单击选中文件，⌘点选可多选，双击预览，拖出可交给 Finder 或其他应用。
- 复制按钮或右键「复制文件」可复制真实文件引用，在 Finder 按 ⌘V 即可复制过去。
- 右键可创建副本、重命名、移动到真实文件夹、复制到外部目录。
- 文件夹支持嵌套；「全部」递归显示项目全部文件，分类显示该目录及子目录的文件。
- 默认删除会把磁盘文件移到系统废纸篓。右键「永久删除」在确认后直接删除磁盘文件，无法从废纸篓恢复。
- 删除项目会移除其任务、备忘和链接，并把整个项目文件夹移到废纸篓；如需完整恢复项目，先做完整备份。
- Finder 中新增、修改或删除文件后，应用每 3 秒刷新；也可以点击刷新按钮。

同名导入/复制会生成 `文件 (2).png`，不会覆盖已有文件。批量操作如有部分失败会显示明细；重试前检查已成功的文件。忽略隐藏文件和符号链接，不允许文件操作越过所选资料库。

## 完整备份

「导出备份」选择资料库外的保存位置，生成 `.boardbackup` 文件包，包含索引和所有真实原始文件。可以在 Finder 右键「显示包内容」检查。

「导入」选择备份文件包，**合并**到当前资料库。已有项目不覆盖，同名项目加「（导入）」并使用独立文件夹。备份源不被修改。备份/恢复期间请勿在 Finder 同时改动相关目录。

当前「导入」只处理归拢导出的完整备份；其他来源的原始文件可以直接拖入项目，不能仅凭截图还原原始资料。

## 技术选择

采用 **SwiftUI + AppKit + Foundation FileManager + ImageIO**，不用 Electron、WebView 或浏览器数据库。SwiftUI 实现截图中的双栏和分页结构，AppKit 提供系统文件对话框、富文本编辑、剪贴板、Finder 集成和废纸篓；原图直接存文件系统，轻量结构数据以 JSON 原子写入。没有网络服务、在线账户或运行时第三方依赖。

对仅面向 Mac 的个人工具，这套方案可直接调用系统文件能力，应用体积小，也便于以后扩展菜单、快捷键和 Quick Look。若未来需要 Windows 版，再评估 Tauri；当前不引入跨平台运行层。

## 开发与验证

需要 Apple Command Line Tools（`xcode-select --install`），无需完整 Xcode：

```sh
/bin/zsh scripts/build.sh
# 生成拖拽安装的通用 DMG
/bin/zsh scripts/dmg.sh
env CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" \
    SWIFT_MODULECACHE_PATH="$PWD/.build/ModuleCache" \
    swift run --disable-sandbox --cache-path .build/cache BoardCoreChecks
```

`--disable-sandbox` 仅为 Swift Package Manager 的构建选项，应用本身也不附加 `com.apple.security.app-sandbox` entitlement。`scripts/build.sh` 生成图标、应用包并做本地临时签名，不触碰资料目录。

文件层检查使用真实临时目录，覆盖原字节复制、同名保护、递归导入、Finder 变更、永久删除、路径和符号链接边界、损坏索引保护、真实重命名/移动/导出、完整备份与失败回滚。不会操作用户已有文件。

使用隔离资料库启动：

```sh
open -n build/归拢.app --args --library /某个可写目录/测试资料库
```

主要代码：`Sources/BoardCore` 是文件与数据层，`Sources/ProjectBoard` 是原生界面，`Tests/BoardCoreTests` 是无需 XCTest 的验证程序。

## 开源许可

归拢使用 [MIT License](LICENSE) 开源。项目主页：<https://github.com/yolaucn/gatherboard>。
