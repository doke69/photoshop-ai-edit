import Foundation
func expect(_ condition: Bool, _ message: String) { if !condition { fatalError(message) } }
let fm = FileManager.default
let work = fm.temporaryDirectory.appendingPathComponent("ai-edit-installer-test-" + UUID().uuidString)
try fm.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: work) }
let payload = work.appendingPathComponent("payload")
try fm.createDirectory(at: payload, withIntermediateDirectories: true)
let manifest: [String: Any] = ["id":"com.local.lk888.psedit","name":"AI 局部改图","version":"0.4.3","host":["minVersion":"25.0.0"]]
try JSONSerialization.data(withJSONObject: manifest).write(to: payload.appendingPathComponent("manifest.json"))
try Data("plugin-source".utf8).write(to: payload.appendingPathComponent("main.js"))
let support = work.appendingPathComponent("Adobe/UXP")
let first = try installPlugin(payload: payload, support: support)
expect(fm.fileExists(atPath: first.destination.appendingPathComponent("main.js").path), "Fresh install missing payload")
let registry = support.appendingPathComponent("PluginsInfo/v1/PS.json")
var root = try JSONSerialization.jsonObject(with: Data(contentsOf: registry)) as! [String: Any]
var records = root["plugins"] as! [[String: Any]]
records.append(["pluginId":"another.plugin","path":"do-not-change","status":"enabled"])
root["plugins"] = records; root["preservedField"] = "keep"
try JSONSerialization.data(withJSONObject: root).write(to: registry)
let privateData = support.appendingPathComponent("PluginsStorage/PHSP/27/External/com.local.lk888.psedit/secret")
try fm.createDirectory(at: privateData.deletingLastPathComponent(), withIntermediateDirectories: true)
try Data("private-fixture".utf8).write(to: privateData)
let second = try installPlugin(payload: payload, support: support)
let updated = try JSONSerialization.jsonObject(with: Data(contentsOf: registry)) as! [String: Any]
expect((updated["plugins"] as! [[String: Any]]).count == 2, "Other plugin registry lost")
expect(updated["preservedField"] as? String == "keep", "Unrelated registry property lost")
expect(try String(contentsOf: privateData, encoding: .utf8) == "private-fixture", "Private storage changed")
expect(fm.fileExists(atPath: second.backup.appendingPathComponent(first.destination.lastPathComponent).path), "Upgrade backup missing")
// Fail after moving plugin folders: rollback must restore them.
let rollbackSupport = work.appendingPathComponent("rollback")
let rollbackFirst = try installPlugin(payload: payload, support: rollbackSupport)
let rollbackRegistry = rollbackSupport.appendingPathComponent("PluginsInfo/v1/PS.json")
let rollbackBytes = try Data(contentsOf: rollbackRegistry)
do {
    _ = try installPlugin(payload: payload, support: rollbackSupport, registryWriter: { _, _ in throw InstallerFailure(message: "Simulated registry write failure") })
    fatalError("Registry write failure ignored")
} catch { }
expect(fm.fileExists(atPath: rollbackFirst.destination.appendingPathComponent("main.js").path), "Rollback lost original plugin")
expect(try Data(contentsOf: rollbackRegistry) == rollbackBytes, "Rollback changed original registry")
let original = try Data(contentsOf: registry)
try Data("invalid-registry".utf8).write(to: registry)
do { _ = try installPlugin(payload: payload, support: support); fatalError("Invalid registry accepted") } catch { }
expect(try String(contentsOf: registry, encoding: .utf8) == "invalid-registry", "Invalid registry was overwritten")
try original.write(to: registry)
let occupied = work.appendingPathComponent("occupied")
let occupiedTarget = occupied.appendingPathComponent("Plugins/External/com.local.lk888.psedit_0.4.3")
try fm.createDirectory(at: occupiedTarget, withIntermediateDirectories: true)
try Data("do-not-overwrite".utf8).write(to: occupiedTarget.appendingPathComponent("keep"))
do { _ = try installPlugin(payload: payload, support: occupied); fatalError("Unrelated target overwritten") } catch { }
expect(fm.fileExists(atPath: occupiedTarget.appendingPathComponent("keep").path), "Unrelated files removed")
print("Installer fixture checks passed: fresh install, upgrade backup, registry preservation, private data retention, rollback, invalid registry and occupied target.")

// The uninstaller removes only this plugin and can be repeated safely.
let uninstallRegistryBytes = try Data(contentsOf: registry)
do {
    _ = try uninstallPlugin(support: support, registryWriter: { _, _ in throw InstallerFailure(message: "Simulated uninstall write failure") })
    fatalError("Uninstall registry write failure ignored")
} catch { }
expect(fm.fileExists(atPath: second.destination.appendingPathComponent("main.js").path), "Uninstall rollback lost plugin")
expect(try Data(contentsOf: registry) == uninstallRegistryBytes, "Uninstall rollback changed registry")
let removed = try uninstallPlugin(support: support)
expect(removed.versions == ["0.4.3"], "Uninstall version mismatch")
expect(!fm.fileExists(atPath: second.destination.path), "Uninstall left plugin folder")
expect(fm.fileExists(atPath: removed.backup!.appendingPathComponent(second.destination.lastPathComponent).path), "Uninstall backup missing")
let remaining = try JSONSerialization.jsonObject(with: Data(contentsOf: registry)) as! [String: Any]
expect((remaining["plugins"] as! [[String: Any]]).count == 1, "Uninstall removed another plugin")
expect(remaining["preservedField"] as? String == "keep", "Uninstall lost registry metadata")
expect(try String(contentsOf: privateData, encoding: .utf8) == "private-fixture", "Uninstall removed private storage")
let repeated = try uninstallPlugin(support: support)
expect(repeated.versions.isEmpty && repeated.backup == nil, "Repeated uninstall should do nothing")
print("Uninstall fixture checks passed: selective removal, backup, data retention, rollback, repeat operation.")

// Simulate an Adobe component updating PS.json after files were staged, while
// the installer still holds its original snapshot.
let concurrent = work.appendingPathComponent("concurrent")
let originalInstall = try installPlugin(payload: payload, support: concurrent)
let concurrentRegistry = concurrent.appendingPathComponent("PluginsInfo/v1/PS.json")
func externalRegistryUpdate(_ registry: URL, _ otherID: String) throws {
    var root = try JSONSerialization.jsonObject(with: Data(contentsOf: registry)) as! [String: Any]
    var records = root["plugins"] as! [[String: Any]]
    records.append(["pluginId": otherID, "path": "new-path", "revision": 7])
    root["plugins"] = records; root["externalRevision"] = otherID
    try JSONSerialization.data(withJSONObject: root).write(to: registry, options: .atomic)
}
_ = try installPlugin(payload: payload, support: concurrent, beforeRegistryCommit: { try externalRegistryUpdate($0, "late.install") })
var latest = try JSONSerialization.jsonObject(with: Data(contentsOf: concurrentRegistry)) as! [String: Any]
expect((latest["plugins"] as! [[String: Any]]).contains { $0["pluginId"] as? String == "late.install" }, "Install lost concurrent plugin")
expect(latest["externalRevision"] as? String == "late.install", "Install lost concurrent metadata")
_ = try uninstallPlugin(support: concurrent, beforeRegistryCommit: { try externalRegistryUpdate($0, "late.uninstall") })
latest = try JSONSerialization.jsonObject(with: Data(contentsOf: concurrentRegistry)) as! [String: Any]
expect((latest["plugins"] as! [[String: Any]]).count == 2, "Uninstall lost concurrent plugins")
expect(latest["externalRevision"] as? String == "late.uninstall", "Uninstall lost concurrent metadata")
_ = try installPlugin(payload: payload, support: concurrent)
do {
    _ = try uninstallPlugin(support: concurrent, registryWriter: { data, url in
        try data.write(to: url, options: .atomic)
        try externalRegistryUpdate(url, "late.rollback")
        throw InstallerFailure(message: "Failure after registry write")
    })
    fatalError("Post-write failure ignored")
} catch { }
latest = try JSONSerialization.jsonObject(with: Data(contentsOf: concurrentRegistry)) as! [String: Any]
expect(latest["externalRevision"] as? String == "late.rollback", "Rollback overwrote concurrent metadata")
expect((latest["plugins"] as! [[String: Any]]).contains { $0["pluginId"] as? String == "late.rollback" }, "Rollback removed concurrent plugin")
expect((latest["plugins"] as! [[String: Any]]).contains { $0["pluginId"] as? String == "com.local.lk888.psedit" }, "Rollback did not restore own record")
expect(fm.fileExists(atPath: originalInstall.destination.appendingPathComponent("main.js").path), "Rollback lost own files")
let registryLock = try RegistryLock(registry: concurrentRegistry)
do { _ = try uninstallPlugin(support: concurrent); fatalError("Concurrent installer lock ignored") }
catch is InstallerFailure { }
registryLock.release()
_ = try uninstallPlugin(support: concurrent)
print("Concurrent registry checks passed: install/uninstall latest merge, selective post-write rollback and exclusive installer lock.")
