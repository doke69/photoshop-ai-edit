import AppKit
import SwiftUI

final class InstallState: ObservableObject {
    @Published var phase = "ready"
    @Published var operation = "install"
    @Published var detail = ""
    @Published var backup: URL?
    let resources: URL
    let version: String
    let preview: Bool
    init(resources: URL, preview: Bool) {
        self.resources = resources; self.preview = preview
        let data = try? Data(contentsOf: resources.appendingPathComponent("plugin/manifest.json"))
        let manifest = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        version = manifest?["version"] as? String ?? "0.4.3"
    }
    func install() {
        guard !preview, phase != "installing" else { return }
        if NSWorkspace.shared.runningApplications.contains(where: { ($0.bundleIdentifier ?? "").hasPrefix("com.adobe.Photoshop") }) {
            phase = "error"; detail = "请保存文件并完全退出 Photoshop，然后点击重试。安装器不会关闭你的文档。"; return
        }
        phase = "installing"; detail = "正在备份并更新插件文件…"
        let payload = resources.appendingPathComponent("plugin", isDirectory: true)
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Adobe/UXP", isDirectory: true)
        DispatchQueue.global(qos: .userInitiated).async {
            let removing = self.operation == "uninstall"
            let result: Result<URL?, Error> = Result {
                if removing { return try uninstallPlugin(support: support).backup }
                return try installPlugin(payload: payload, support: support).backup
            }
            DispatchQueue.main.async {
                switch result {
                case .success(let backup): self.backup = backup; self.phase = "success"; self.detail = removing ? "插件已卸载，API Key 与历史数据保留。" : "打开 Photoshop，在「增效工具」中找到「AI 局部改图」。"
                case .failure(let error): self.phase = "error"; self.detail = error.localizedDescription
                }
            }
        }
    }
    func guide() { if !preview { NSWorkspace.shared.open(resources.appendingPathComponent("安装与使用指南.html")) } }
}

struct InstallerView: View {
    @ObservedObject var state: InstallState
    let accent = Color(red: 0.35, green: 0.67, blue: 1)
    var success: Bool { state.phase == "success" }
    var removing: Bool { state.operation == "uninstall" }
    var working: Bool { state.phase == "installing" }
    func step(_ number: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundColor(accent)
                .frame(width: 26, height: 26).background(accent.opacity(0.12)).cornerRadius(8)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                Text(text).font(.system(size: 12)).foregroundColor(Color.white.opacity(0.53)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if let logo = NSImage(contentsOf: state.resources.appendingPathComponent("AppIcon.png")) {
                    Image(nsImage: logo).resizable().interpolation(.high).frame(width: 96, height: 96).shadow(color: .black.opacity(0.3), radius: 20, y: 8)
                }
                Text("PHOTOSHOP").font(.system(size: 10, weight: .bold)).tracking(2.5).foregroundColor(accent).padding(.top, 24)
                Text("AI Edit").font(.system(size: 39, weight: .bold)).tracking(-1).foregroundColor(.white).padding(.top, 6)
                Text("只改你想改的地方。") .font(.system(size: 15, weight: .medium)).foregroundColor(Color.white.opacity(0.78)).padding(.top, 12)
                Text("框选 · 描述 · 生成 · 回填图层").font(.system(size: 11)).foregroundColor(Color.white.opacity(0.4)).padding(.top, 9)
                Spacer()
                HStack(spacing: 6) { Circle().fill(Color(red: 0.4, green: 0.85, blue: 0.72)).frame(width: 5, height: 5); Text("macOS 通用版 · v" + state.version).font(.system(size: 10)).foregroundColor(Color.white.opacity(0.5)) }
            }
            .padding(.horizontal, 30).padding(.top, 58).padding(.bottom, 30).frame(width: 270)
            .background(LinearGradient(colors: [Color(red: 0.08, green: 0.15, blue: 0.24), Color(red: 0.05, green: 0.08, blue: 0.13)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: success ? "checkmark.circle.fill" : "shippingbox").foregroundColor(success ? .green : accent)
                    Text(success ? (removing ? "卸载完成" : "安装完成") : "插件管理向导").font(.system(size: 11, weight: .medium)).foregroundColor(Color.white.opacity(0.55))
                }
                Text(success ? (removing ? "已卸载，数据已保留。" : "已准备好，开始创作。") : removing ? "卸载插件，保留你的数据。" : "把 AI 带进你的工作流。")
                    .font(.system(size: 23, weight: .semibold)).tracking(-0.5).foregroundColor(.white).padding(.top, 15)
                Text(removing ? "只移除 AI 局部改图的文件与登记，不影响其他插件。" : success ? "接下来完成 API 设置，即可开始第一次局部改图。" : "安装到当前用户，无需管理员权限或开发工具。")
                    .font(.system(size: 12)).foregroundColor(Color.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true).padding(.top, 9)
                if !success && !working {
                    HStack(spacing: 4) {
                        ForEach(["install", "uninstall"], id: \.self) { operation in
                            Button(operation == "install" ? "安装 / 更新" : "卸载插件") { state.operation = operation; state.phase = "ready"; state.detail = "" }
                                .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundColor(state.operation == operation ? .white : Color.white.opacity(0.45))
                                .padding(.horizontal, 14).padding(.vertical, 7).background(state.operation == operation ? Color.white.opacity(0.1) : Color.clear).cornerRadius(6)
                        }
                    }.padding(3).background(Color.black.opacity(0.18)).cornerRadius(8).padding(.top, 20)
                }
                VStack(alignment: .leading, spacing: 20) {
                    if removing {
                        step("01", success ? "插件文件已移除" : "保存文件，退出 Photoshop", success ? "下次启动 Photoshop 后生效" : "卸载前请完全退出，以免文件仍被占用")
                        step("02", "API Key 与历史数据保留", "重新安装后，可继续使用原来的配置与记录")
                        step("03", "其他插件不受影响", "旧插件文件和登记自动保存为本机备份")
                    } else if success {
                        step("01", "打开 AI 局部改图", "Photoshop → 增效工具 → AI 局部改图")
                        step("02", "连接你的 API", "获取并保存 Key，检查连接并同步模型")
                        step("03", "从一个选区开始", "框选区域，填写要求，生成后添加为图层")
                    } else {
                        step("01", "保存文件，退出 Photoshop", "完成安装后重新打开，即可载入插件")
                        step("02", "一键安装，保留你的数据", "旧版文件自动备份，保留 Key 与任务历史")
                        step("03", "按引导完成 API 设置", "检查连接不会提交付费生图任务")
                    }
                }.padding(.top, 24)
                Spacer(minLength: 16)
                if state.phase == "error" {
                    HStack(alignment: .top, spacing: 8) { Image(systemName: "exclamationmark.circle"); Text(state.detail).fixedSize(horizontal: false, vertical: true) }
                        .font(.system(size: 11)).foregroundColor(Color(red: 1, green: 0.73, blue: 0.58)).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.08)).cornerRadius(8).padding(.bottom, 12)
                }
                if working {
                    HStack(spacing: 10) { ProgressView().scaleEffect(0.6).frame(width: 16, height: 16); Text(state.detail).font(.system(size: 11)).foregroundColor(Color.white.opacity(0.7)) }.padding(.bottom, 12)
                }
                Button(action: { if success { if removing { NSApp.terminate(nil) } else { state.guide() } } else { state.install() } }) {
                    HStack { Spacer(); Text(success ? (removing ? "完成" : "打开使用指南") : working ? "正在处理…" : state.phase == "error" ? "重试" : removing ? "卸载插件（保留数据）" : "安装 AI 局部改图").font(.system(size: 14, weight: .semibold)); Image(systemName: success ? "arrow.up.right" : "arrow.right").font(.system(size: 12, weight: .semibold)); Spacer() }
                    .foregroundColor(.white).frame(height: 42).background((removing && !success ? Color(red: 0.66, green: 0.27, blue: 0.25) : Color(red: 0.16, green: 0.45, blue: 0.92))).cornerRadius(10)
                }.buttonStyle(.plain).disabled(working)
                HStack {
                    Text("Photoshop 2024 / 25.0 及以上").font(.system(size: 10)).foregroundColor(Color.white.opacity(0.35))
                    Spacer()
                    Button(success ? "完成" : "稍后操作") { if !state.preview { NSApp.terminate(nil) } }.buttonStyle(.plain).font(.system(size: 11)).foregroundColor(Color.white.opacity(0.55)).disabled(working)
                }.padding(.top, 14)
            }.padding(.horizontal, 30).padding(.top, 49).padding(.bottom, 28).frame(maxWidth: .infinity)
             .background(Color(red: 0.075, green: 0.085, blue: 0.105))
        }.frame(width: 760, height: 540).preferredColorScheme(.dark)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let arguments = CommandLine.arguments
let screenshotIndex = arguments.firstIndex(of: "--preview-screenshot")
let appIconIndex = arguments.firstIndex(of: "--preview-app-icon")
let preview = screenshotIndex != nil || appIconIndex != nil
let resources: URL
if let index = arguments.firstIndex(of: "--resources"), arguments.count > index + 1 { resources = URL(fileURLWithPath: arguments[index + 1]) }
else { resources = Bundle.main.resourceURL! }
if let icon = NSImage(contentsOf: resources.appendingPathComponent("AppIcon.icns")) { app.applicationIconImage = icon }
// Export the very image assigned to the Dock, without opening an installable UI.
if let index = appIconIndex, arguments.count > index + 1 {
    guard let image = app.applicationIconImage,
          let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 512, pixelsHigh: 512, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(5) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.clear(CGRect(x: 0, y: 0, width: 512, height: 512))
    image.draw(in: NSRect(x: 0, y: 0, width: 512, height: 512), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(6) }
    do { try data.write(to: URL(fileURLWithPath: arguments[index + 1])); exit(0) } catch { exit(7) }
}
let state = InstallState(resources: resources, preview: preview)
if preview, arguments.contains("--preview-uninstall") { state.operation = "uninstall" }
if preview, arguments.contains("--preview-complete") { state.phase = "success" }
if preview, arguments.contains("--preview-error") { state.phase = "error"; state.detail = "请保存文件并完全退出 Photoshop，然后点击重试。" }
let hosting = NSHostingView(rootView: InstallerView(state: state))
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 540), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
window.title = "Photoshop AI Edit"
window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
window.appearance = NSAppearance(named: .darkAqua)
window.isMovableByWindowBackground = true
window.contentView = hosting; window.center(); window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
if let index = screenshotIndex, arguments.count > index + 1 {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { exit(2) }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(3) }
        do { try data.write(to: URL(fileURLWithPath: arguments[index + 1])); exit(0) } catch { exit(4) }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool { state.phase != "installing" }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { state.phase == "installing" ? .terminateCancel : .terminateNow }
}
let delegate = AppDelegate(); app.delegate = delegate; window.delegate = delegate
app.run()
