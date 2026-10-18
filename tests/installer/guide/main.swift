import Foundation
let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("AI Edit 指南测试 " + UUID().uuidString)
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }
let source = root.appendingPathComponent("安装器.app/Contents/Resources")
try fm.createDirectory(at: source, withIntermediateDirectories: true)
let html = Data("<!doctype html><html lang='zh-CN'><p id='first-open'>安装与使用指南</p></html>".utf8)
try html.write(to: source.appendingPathComponent("安装与使用指南.html"))
let destination = root.appendingPathComponent("用户数据/Guides")
let file = try prepareGuide(resources: source, destinationRoot: destination, version: "0.4.8")
guard try Data(contentsOf: file) == html else { throw InstallerFailure(message: "Guide bytes changed") }
let target = try guideURL(file: file, anchor: "first-open")
guard target.isFileURL, target.fragment == "first-open", target.path == file.path else { throw InstallerFailure(message: "Broken guide fragment / Chinese path") }
_ = try prepareGuide(resources: source, destinationRoot: destination, version: "0.4.8")
do { _ = try prepareGuide(resources: source, destinationRoot: destination, version: "../outside"); throw NSError(domain: "test", code: 1) }
catch is InstallerFailure { }
try fm.removeItem(at: source)
guard try Data(contentsOf: file) == html else { throw InstallerFailure(message: "Guide lost after eject / exit") }
do { _ = try prepareGuide(resources: source, destinationRoot: destination, version: "0.4.8"); throw NSError(domain: "test", code: 2) }
catch is CocoaError { }
print("PASS guide: Chinese paths, spaces, atomic replacement, version validation, fragment and persistence after source removal.")
