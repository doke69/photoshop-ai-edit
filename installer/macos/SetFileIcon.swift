import AppKit
let args = CommandLine.arguments
guard args.count == 3 else { exit(1) }
if args[1] == "--clear" {
    guard FileManager.default.fileExists(atPath: args[2]) else { exit(2) }
    // Already-default files may return false; clearing is intentionally idempotent.
    _ = NSWorkspace.shared.setIcon(nil, forFile: args[2], options: [])
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    exit(0)
}
let icon: NSImage
if URL(fileURLWithPath: args[1]).pathExtension == "app" {
    // Use the system-rendered application icon, including the current macOS shape.
    icon = NSWorkspace.shared.icon(forFile: args[1])
} else {
    guard let image = NSImage(contentsOfFile: args[1]), image.isValid else { exit(1) }
    icon = image
}
guard NSWorkspace.shared.setIcon(icon, forFile: args[2], options: []) else { exit(2) }
RunLoop.current.run(until: Date().addingTimeInterval(0.3))
