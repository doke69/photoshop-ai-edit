# Photoshop AI Edit 专用安装器

安装器只处理 `com.local.lk888.psedit`，采用当前用户目录侧载：无需 UXP 开发工具或 Node.js。Mac 使用 SwiftUI 双栏安装 / 卸载界面（由 AppKit 承载），Windows 使用 WPF 图形界面、单文件 EXE 与 PowerShell 5.1 安装内核。安装包不包含用户密钥、任务历史或其他本机配置。

## 构建

在 macOS 安装 Xcode 命令行工具后，从项目根目录运行：

```sh
python3 scripts/package.py --installers
```

输出到 `dist/`：CCX、Mac universal DMG 与安装器 ZIP、Windows 安装包 ZIP、离线 HTML 指南、SHA256 校验文件。Mac 安装器仅作临时签名，没有 Apple Developer ID 签名与公证。Windows 包内 PowerShell 使用 UTF-8 BOM，脚本入口使用 CRLF，兼容 Windows PowerShell 的中文路径读取。

## 安装策略

- 安装前要求 Photoshop 完全退出。
- 读取并校验捆绑清单，只安装本插件。
- 使用 `Adobe/UXP/Plugins/External/<id>_<version>`；登记文件为 `PluginsInfo/v1/PS.json`。
- Windows 登记路径使用 `$localPlugins\External\<id>_<version>`，Mac 使用正斜杠。
- 安装前测试目录是否可写；暂存复制后复核清单；更新登记时保留其他插件与未知字段。
- 本插件旧目录及旧登记备份到 `Plugins/.AIEditInstallerBackups`。发生写入失败时恢复旧登记与旧目录。
- 不访问 `PluginsStorage`、安全存储或 API；安装成功后可打开离线指南。
- 侧载插件由此安装器管理，不会变成 Creative Cloud 管理的官方安装。无法侧载时使用同版本 CCX 与 OpenUXP。

## OpenUXP 对照记录

用户要求参考 OpenUXP；核对了 [yArna/OpenUPX-Installer](https://github.com/yArna/OpenUPX-Installer) 的 [src-tauri/src/lib.rs](https://github.com/yArna/OpenUPX-Installer/blob/52769f091548f8b2384f96dafcc0a838b0cc10a3/src-tauri/src/lib.rs)，提交 `52769f091548f8b2384f96dafcc0a838b0cc10a3`。

对照范围：`build_sideload_preflight`、`prepare_registry_update`、`sideload_ccx` 的目录、登记字段、平台路径、暂存复核和回滚流程。本安装器以 Swift / PowerShell 独立实现，不捆绑或复制其 Rust / Tauri 源码；不包含通用 CCX 解压、其他 Adobe 宿主、CEP 支持或 UPIA 官方安装功能。

## 验证

```sh
node --test tests/*.test.cjs
xcrun swiftc -module-cache-path /private/tmp/ps-edit-swift-cache installer/macos/InstallerCore.swift tests/installer/main.swift -o /private/tmp/ps-edit-installer-tests
/private/tmp/ps-edit-installer-tests
```

Swift 检查在隔离临时目录中验证首次安装、同版本升级、其他插件登记及私有数据保留、写入失败回滚、损坏登记保护、目标占用保护；不会写入真实 Adobe 用户目录。Mac 安装界面、真实 Photoshop 加载与 Windows 安装仍需实机验证，不将构建成功等同于安装验证通过。

## 卸载

Mac：打开 DMG 中的安装器，切换「卸载插件」。Windows：重新打开图形安装器，切换「卸载插件」；旧 ZIP 包可双击 `Uninstall.cmd`。卸载只移除本插件登记并将文件移到备份目录，保留插件安全存储与任务历史，支持重复执行。Mac 隔离目录检查覆盖卸载数据保留、其他插件保留、备份和登记失败回滚。

应用图标源文件位于 `assets/branding/app-icon.png`，使用内置 imagegen 生成，提示词记录在 `assets/branding/PROMPT.md`。打包时生成 16–1024 像素的 ICNS，嵌入安装应用；DMG 卷使用 `assets/branding/mounted-disk.png` 的深蓝色品牌磁盘图标。

## 图标与离线指南更新

图标母版为 1024 × 1024，背景铺满画布，不嵌套小底板；使用原生 `iconutil` 输出 ICNS，配置到应用清单并在启动时设置应用图标。磁盘卷采用深蓝色磁盘外形、品牌图形直接位于正面的设计；独立方形 Logo 用于安装应用。先设置可写卷图标，再压缩为 DMG，确保挂载图标随安装包分发。本地 DMG 文件也设置同款自定义图标；文件扩展属性在普通 HTTP 下载后可能丢失，但卷内图标始终保留。

离线 HTML 指南内嵌 Logo，无需联网加载图片；重新分为四步操作与维护 FAQ。GPT2.5 价格优先参考价按维护者确认的人民币 ¥0.025 / 张标注，注明信息日期及平台实际计费规则；不改写插件模型 ID、默认参数或请求路由。

## 磁盘图标

安装应用使用 AI Edit 方形 Logo；挂载到桌面的磁盘卷使用已审核的深蓝色品牌磁盘图标。图标来源与提示词见 `assets/branding/VOLUME-ICON.md`。已挂载的旧映像需推出后重新打开新版。

## Windows 图形安装器

在 Windows 10 / 11（.NET Framework 4.8、Windows PowerShell 5.1）运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File installer/windows/build.ps1
```

构建输出 `dist/Photoshop-AI-Edit-<version>-Windows-Setup.exe` 与独立 SHA256 文件。EXE 内嵌插件、安装内核、品牌 Logo 和离线指南，运行时解压到随机临时目录，退出后清理，无需 Node.js、Python 或管理员权限。Python 仅是构建依赖。安装成功后可查看 API 指南；卸载保留 Key 和历史。失败时可另存本次操作的诊断记录，不读取密钥或任务内容。EXE 尚无代码签名，Windows 可能提示发布者未知。

界面沿用 Mac 的深蓝品牌栏、操作切换和三步说明，支持键盘焦点；小屏幕会缩放完整界面，长错误可滚动。没有调用平台 API 的代码。

`.github/workflows/windows-installer.yml` 在 Windows Server 2022 编译，并运行 `tests/installer/windows.ps1` 与 `windows-gui.ps1`。前者在临时目录覆盖中文路径、带 BOM 登记、首次安装、升级、元数据与其他插件保留、私有数据保留、安装及卸载回滚、重复卸载、异常登记和目标占用。后者启动最终 EXE，通过 Windows UI Automation 点击安装及卸载，并检查实际内嵌插件的文件哈希，另生成只读预览截图。`--preview <png>` 明确禁用安装及指南打开，也不访问 Adobe 目录。

这些检查不等于 Windows 10 / 11 用户电脑上的 Photoshop 实机验证。Mac 的安装器及已发布 DMG 不受此更改影响。WPF 构建参考 [Microsoft 文档](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/app-development/building-a-wpf-application-wpf?view=netframeworkdesktop-4.8)，云端验证环境见 [GitHub 托管运行器](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)。

### EXE 文件图标

Windows EXE 通过 `/win32icon` 内嵌品牌 Logo，包含 16、24、32、48、64、128、256 像素；安装窗口也使用品牌图标。构建另外输出 `Photoshop-AI-Edit-<version>-Windows.ico`，可用于手动修改快捷方式图标。Mac Finder 不一定读取 Windows PE 内嵌图标，应以 Windows 资源管理器为准。

`tests/installer/windows-icons.ps1` 调用 Windows Shell 原生接口从 EXE 提取 256 像素图标，并验证尺寸与品牌颜色，输出实际图标预览。手动运行 Windows workflow 时，可填写 `published_version`，额外下载并检查已经发布的 EXE；默认只检查本次构建，不依赖尚未发布的新版本。
