import Foundation
import Darwin

struct InstallerFailure: LocalizedError { let message: String; var errorDescription: String? { message } }
// All AI Edit installers share this lock. Keep the file in place so another
// process never locks a different inode while an operation is still active.
final class RegistryLock {
    private var descriptor: Int32 = -1
    init(registry: URL) throws {
        try FileManager.default.createDirectory(at: registry.deletingLastPathComponent(), withIntermediateDirectories: true)
        let path = registry.deletingLastPathComponent().appendingPathComponent(".ai-edit-installer.lock").path
        descriptor = Darwin.open(path, O_CREAT | O_RDWR, mode_t(0o600))
        guard descriptor >= 0 else { throw InstallerFailure(message: "无法锁定插件登记，请检查目录权限。") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor); descriptor = -1
            throw InstallerFailure(message: "另一个 AI Edit 安装器正在操作，请稍后重试。")
        }
    }
    func release() { if descriptor >= 0 { flock(descriptor, LOCK_UN); Darwin.close(descriptor); descriptor = -1 } }
    deinit { release() }
}

private func registryBytes(_ url: URL) throws -> Data? {
    FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
}
private func registrySnapshot(_ url: URL) throws -> (bytes: Data?, root: [String: Any]) {
    let bytes = try registryBytes(url)
    guard let bytes = bytes else { return (nil, ["plugins": [[String: Any]]()]) }
    guard let root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], root["plugins"] is [[String: Any]] else {
        throw InstallerFailure(message: "插件登记格式异常，未覆盖登记文件。")
    }
    return (bytes, root)
}

// Re-read after staging / backup and only merge this plugin. Adobe components
// may not honor our lock, so also check for a change immediately before writing.
private func commitPluginRegistry(_ registry: URL, values: [String: Any]?, writer: (Data, URL) throws -> Void) throws {
    let id = "com.local.lk888.psedit", before = try registrySnapshot(registry)
    let records = before.root["plugins"] as! [[String: Any]]
    var own = records.filter { $0["pluginId"] as? String == id }
    if let values = values {
        var entry = own.first ?? [:]
        values.forEach { entry[$0.key] = $0.value }; own = [entry]
    } else { own = [] }
    var root = before.root
    root["plugins"] = records.filter { $0["pluginId"] as? String != id } + own
    let output = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    guard try registryBytes(registry) == before.bytes else { throw InstallerFailure(message: "插件登记已被其他程序修改，请重试。") }
    do { try writer(output, registry) }
    catch {
        // Never restore the old whole-file snapshot over a newer third-party
        // update. Undo only our entry, and only if it still matches our write.
        if let current = try? registrySnapshot(registry), let bytes = current.bytes, bytes != before.bytes {
            let currentRecords = current.root["plugins"] as! [[String: Any]]
            let currentOwn = currentRecords.filter { $0["pluginId"] as? String == id }
            if NSArray(array: currentOwn).isEqual(to: own) {
                if bytes == output, (try? registryBytes(registry)) == bytes {
                    if let original = before.bytes { try? original.write(to: registry, options: .atomic) }
                    else { try? FileManager.default.removeItem(at: registry) }
                } else {
                    var restored = current.root
                    restored["plugins"] = currentRecords.filter { $0["pluginId"] as? String != id } + records.filter { $0["pluginId"] as? String == id }
                    if let data = try? JSONSerialization.data(withJSONObject: restored, options: [.prettyPrinted, .sortedKeys]),
                       (try? registryBytes(registry)) == bytes { try? data.write(to: registry, options: .atomic) }
                }
            }
        }
        throw error
    }
}

struct InstallResult { let version: String; let destination: URL; let backup: URL }
func installPlugin(payload: URL, support: URL, registryWriter: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }, beforeRegistryCommit: ((URL) throws -> Void)? = nil) throws -> InstallResult {
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
    let lock = try RegistryLock(registry: registry); defer { lock.release() }
    let original = try registrySnapshot(registry).bytes
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
    var moved: [URL] = []; var placed = false
    defer { try? fm.removeItem(at: stage) }
    do {
        try fm.copyItem(at: payload, to: stage)
        guard try Data(contentsOf: stage.appendingPathComponent("manifest.json")) == manifestBytes else {
            throw InstallerFailure(message: "安装文件在读取过程中发生变化，已停止安装。")
        }
        for entry in old { try fm.moveItem(at: entry, to: backup.appendingPathComponent(entry.lastPathComponent)); moved.append(entry) }
        try fm.moveItem(at: stage, to: target); placed = true
        try beforeRegistryCommit?(registry)
        let values: [String: Any] = ["hostMinVersion": (info["host"] as? [String: Any])?["minVersion"] as? String ?? "25.0.0",
            "name": info["name"] as? String ?? "AI 局部改图", "path": "$localPlugins/External/" + target.lastPathComponent,
            "pluginId": id, "status": "enabled", "type": "uxp", "versionString": version]
        try commitPluginRegistry(registry, values: values, writer: registryWriter)
        return InstallResult(version: version, destination: target, backup: backup)
    } catch {
        if placed { try? fm.removeItem(at: target) }
        for entry in moved { try? fm.moveItem(at: backup.appendingPathComponent(entry.lastPathComponent), to: entry) }
        throw error
    }
}

struct UninstallResult { let versions: [String]; let backup: URL? }
func uninstallPlugin(support: URL, registryWriter: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }, beforeRegistryCommit: ((URL) throws -> Void)? = nil) throws -> UninstallResult {
    let fm = FileManager.default
    let id = "com.local.lk888.psedit"
    let registry = support.appendingPathComponent("PluginsInfo/v1/PS.json")
    let external = support.appendingPathComponent("Plugins/External", isDirectory: true)
    let lock = try RegistryLock(registry: registry); defer { lock.release() }
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
    var moved: [URL] = []
    do {
        for entry in old { try fm.moveItem(at: entry, to: backup.appendingPathComponent(entry.lastPathComponent)); moved.append(entry) }
        try beforeRegistryCommit?(registry)
        try commitPluginRegistry(registry, values: nil, writer: registryWriter)
        return UninstallResult(versions: versions.sorted(), backup: backup)
    } catch {
        for entry in moved { try? fm.moveItem(at: backup.appendingPathComponent(entry.lastPathComponent), to: entry) }
        throw error
    }
}
