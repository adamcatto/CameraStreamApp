import Foundation

enum BundledTools {
    static var appResourcesDirectory: URL {
        URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
    }

    static func executable(named name: String, in subdirectory: String = "bin") -> URL? {
        let url = appResourcesDirectory
            .appendingPathComponent(subdirectory, isDirectory: true)
            .appendingPathComponent(name)
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static var csshXURL: URL? { executable(named: "csshX") }

    static var bundledToolStatus: String {
        var parts: [String] = ["OpenSSH (/usr/bin/ssh)"]
        if csshXURL != nil { parts.append("csshX (bundled)") }
        else { parts.append("csshX (missing from app bundle)") }
        return parts.joined(separator: ", ")
    }
}
