import Foundation

struct InstallerFailure: LocalizedError { let message: String; var errorDescription: String? { message } }
struct InstallResult { let version: String; let destination: URL; let backup: URL }
func installPlugin(payload: URL, support: URL, registryWriter: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) throws -> InstallResult {
    let fm = FileManager.default
    let manifestBytes = try Data(contentsOf: payload.appendingPathComponent("manifest.json"))
    let manifest = try JSONSerialization.jsonObject(with: manifestBytes) as? [String: Any]
    guard let info = manifest, info["id"] as? String == "com.local.lk888.psedit", let version = info["version"] as? String,
          version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil else {
        throw InstallerFailure(message: "安装文件身份或版本无效，请重新下载完整安装包。")
    }
    let id = "com.local.lk888.psedit"
    let external = support.appendingPathComponent("Plugins/External", isDirectory: true)
    let registry = support.appendingPathComponent("PluginsInfo/v1/PS.json")
    let original = fm.fileExists(atPath: registry.path) ? try Data(contentsOf: registry) : nil
    var root = [String: Any]()
    if let bytes = original {
        guard let parsed = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], parsed["plugins"] is [[String: Any]] else {
            throw InstallerFailure(message: "Adobe 插件登记格式异常，未作任何修改。请先修复登记或使用 OpenUXP 安装。")
        }
        root = parsed
    }
    var plugins = root["plugins"] as? [[String: Any]] ?? []
    let target = external.appendingPathComponent(id + "_" + version, isDirectory: true)
    let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-") + "-" + UUID().uuidString
    let backup = support.appendingPathComponent("Plugins/.AIEditInstallerBackups/" + stamp, isDirectory: true)
    let stage = external.appendingPathComponent(".ai-edit-install-" + UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: external, withIntermediateDirectories: true)
    var old: [URL] = []
    for entry in try fm.contentsOfDirectory(at: external, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
        if (try? entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { continue }
        guard let data = try? Data(contentsOf: entry.appendingPathComponent("manifest.json")),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object["id"] as? String == id else { continue }
        old.append(entry)
    }
    if fm.fileExists(atPath: target.path) && !old.contains(where: { $0.standardizedFileURL.path == target.standardizedFileURL.path }) {
        throw InstallerFailure(message: "安装目标被其他文件占用，未覆盖该目录。")
    }
    // Check both destinations before moving any installed plugin files.
    try fm.createDirectory(at: registry.deletingLastPathComponent(), withIntermediateDirectories: true)
    for directory in [external, registry.deletingLastPathComponent()] {
        let probe = directory.appendingPathComponent(".ai-edit-write-check-" + UUID().uuidString)
        do { try Data().write(to: probe, options: .withoutOverwriting); try fm.removeItem(at: probe) }
        catch { try? fm.removeItem(at: probe); throw InstallerFailure(message: "插件目录无法写入：" + directory.path + "。请检查当前用户权限后重试。") }
    }
    if original != nil && !fm.isWritableFile(atPath: registry.path) { throw InstallerFailure(message: "插件登记不可写，未修改现有插件。") }
    try fm.createDirectory(at: backup, withIntermediateDirectories: true)
    if let bytes = original { try bytes.write(to: backup.appendingPathComponent("PS.json"), options: .atomic) }
    var moved: [URL] = []; var placed = false; var registryTouched = false
    defer { try? fm.removeItem(at: stage) }
    do {
        try fm.copyItem(at: payload, to: stage)
        guard try Data(contentsOf: stage.appendingPathComponent("manifest.json")) == manifestBytes else {
            throw InstallerFailure(message: "安装文件在读取过程中发生变化，已停止安装。")
        }
        for entry in old { try fm.moveItem(at: entry, to: backup.appendingPathComponent(entry.lastPathComponent)); moved.append(entry) }
        try fm.moveItem(at: stage, to: target); placed = true
        var record = plugins.first { $0["pluginId"] as? String == id } ?? [:]
        record["hostMinVersion"] = (info["host"] as? [String: Any])?["minVersion"] as? String ?? "25.0.0"
        record["name"] = info["name"] as? String ?? "AI 局部改图"
        record["path"] = "$localPlugins/External/" + target.lastPathComponent
        record["pluginId"] = id; record["status"] = "enabled"; record["type"] = "uxp"; record["versionString"] = version
        plugins.removeAll { $0["pluginId"] as? String == id }; plugins.append(record); root["plugins"] = plugins
        try fm.createDirectory(at: registry.deletingLastPathComponent(), withIntermediateDirectories: true)
        registryTouched = true
        try registryWriter(JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]), registry)
        return InstallResult(version: version, destination: target, backup: backup)
    } catch {
        if registryTouched { if let bytes = original { try? bytes.write(to: registry, options: .atomic) } else { try? fm.removeItem(at: registry) } }
        if placed { try? fm.removeItem(at: target) }
        for entry in moved { try? fm.moveItem(at: backup.appendingPathComponent(entry.lastPathComponent), to: entry) }
        throw error
    }
}

struct UninstallResult { let versions: [String]; let backup: URL? }
func uninstallPlugin(support: URL, registryWriter: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) throws -> UninstallResult {
    let fm = FileManager.default
    let id = "com.local.lk888.psedit"
    let registry = support.appendingPathComponent("PluginsInfo/v1/PS.json")
    let external = support.appendingPathComponent("Plugins/External", isDirectory: true)
    let original = fm.fileExists(atPath: registry.path) ? try Data(contentsOf: registry) : nil
    var root: [String: Any] = ["plugins": [[String: Any]]()]
    if let bytes = original {
        guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], object["plugins"] is [[String: Any]] else {
            throw InstallerFailure(message: "插件登记格式异常，未卸载任何文件。")
        }
        root = object
    }
    let records = root["plugins"] as! [[String: Any]]
    let matching = records.filter { $0["pluginId"] as? String == id }
    var old: [URL] = []; var versions = Set(matching.compactMap { $0["versionString"] as? String })
    if fm.fileExists(atPath: external.path) {
        for entry in try fm.contentsOfDirectory(at: external, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            if (try? entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { continue }
            guard let bytes = try? Data(contentsOf: entry.appendingPathComponent("manifest.json")),
                  let manifest = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any], manifest["id"] as? String == id else { continue }
            old.append(entry); if let version = manifest["version"] as? String { versions.insert(version) }
        }
    }
    guard !old.isEmpty || !matching.isEmpty else { return UninstallResult(versions: [], backup: nil) }
    let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-") + "-" + UUID().uuidString
    let backup = support.appendingPathComponent("Plugins/.AIEditInstallerBackups/uninstall-" + stamp, isDirectory: true)
    try fm.createDirectory(at: backup, withIntermediateDirectories: true)
    if let bytes = original { try bytes.write(to: backup.appendingPathComponent("PS.json"), options: .atomic) }
    var moved: [URL] = []; var registryTouched = false
    do {
        for entry in old { try fm.moveItem(at: entry, to: backup.appendingPathComponent(entry.lastPathComponent)); moved.append(entry) }
        if !matching.isEmpty {
            root["plugins"] = records.filter { $0["pluginId"] as? String != id }
            registryTouched = true
            try registryWriter(JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]), registry)
        }
        return UninstallResult(versions: versions.sorted(), backup: backup)
    } catch {
        if registryTouched, let bytes = original { try? bytes.write(to: registry, options: .atomic) }
        for entry in moved { try? fm.moveItem(at: backup.appendingPathComponent(entry.lastPathComponent), to: entry) }
        throw error
    }
}
