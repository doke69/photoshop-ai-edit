# v0.4.7 透明圆角图标检查记录

v0.4.5 与 v0.4.6 已撤回为草稿；公开最新版恢复为 v0.4.4。v0.4.7 修正版先保留为草稿，供审核外观。

## 根因与修复

原图的圆角蓝色主体外还有一整块深色背景。前面的检查只证明 EXE 有图标和品牌颜色，没有证明边角透明；Mac Dock 也直接使用了带背景的源图。现将主体外背景抠除，Mac ICNS、运行时 Dock 图像、Mac 安装界面、Windows EXE / WPF 共用 `app-icon.png`，避免各入口使用不同版本。原输入保留在 `windows-installer.png`。

## 已完成的实际检查

- 透明母版：四角、边缘中点和圆角外部采样接近全透明；主体中心接近全不透明。允许抗锯齿带的极低 alpha 值，不允许不透明背景。
- 回归负例：原来带背景的 `windows-installer.png` 被检查程序明确拒绝。
- Mac 最终 DMG：签名校验通过；从包内读取 ICNS 的 10 个位图表示（16–1024 px），逐个通过透明几何检查。
- Mac 原生应用图标：通过 `NSWorkspace.icon(forFile:)` 读出的 1024px 图标通过检查。
- Mac 程序坞用图：运行最终应用的只读 `--preview-app-icon` 入口，导出实际设置给 `NSApplication.applicationIconImage` 的 512px 图像，通过透明检查。不是靠安装界面的圆角遮罩推断 Dock 图标。
- Windows 最终 EXE：Windows Shell 原生读取 16、24、32、48、64、128、256px，逐一核对透明外沿、圆角、主体和品牌颜色。均通过。
- Windows 安装界面：实际执行安装／卸载的 UI 自动检查通过；1x、2x 渲染预览检查通过。
- 白色、深色、棋盘背景：直接绘制系统提取图像，没有对图像施加圆角或裁切遮罩。对照图包含原错误输入，便于检查是否残留方形背景。
- 插件 132 项自动测试通过；未调用付费生图，也未安装到本机真实 Photoshop 目录。

[Windows 构建与检查记录](https://github.com/doke69/photoshop-ai-edit/actions/runs/39106159045)

[系统图标对照图](../readme/icon-system-review-v0.4.7.png) · [Mac 界面](../readme/installer-v0.4.7.png) · [Windows 界面](../readme/windows-installer-v0.4.7.png)

此记录验证的是图标内容和安装器检查，不声称完成所有用户显示器配置或真实 Photoshop 加载测试。使用修正版检查时，应先退出旧安装器，再打开新包，避免继续观察旧进程的 Dock 图像。
