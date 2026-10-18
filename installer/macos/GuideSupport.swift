import Foundation

// Keep the guide outside the app bundle / mounted image. A browser may read it
// asynchronously, after the installer exits or its volume has been ejected.
func prepareGuide(resources: URL, destinationRoot: URL, version: String) throws -> URL {
    guard version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil else {
        throw InstallerFailure(message: "使用指南版本无效，请重新下载安装包。")
    }
    let source = resources.appendingPathComponent("安装与使用指南.html")
    let data = try Data(contentsOf: source)
    guard !data.isEmpty else { throw InstallerFailure(message: "安装包内的使用指南为空，请重新下载。") }
    let directory = destinationRoot.appendingPathComponent(version, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let target = directory.appendingPathComponent("index.html")
    try data.write(to: target, options: .atomic)
    return target
}

func guideURL(file: URL, anchor: String?) throws -> URL {
    var components = URLComponents(url: file, resolvingAgainstBaseURL: false)
    components?.fragment = anchor
    guard let result = components?.url else { throw InstallerFailure(message: "无法生成指南地址。") }
    return result
}
