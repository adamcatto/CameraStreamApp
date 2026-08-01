import Foundation

enum ClusterShell {
    static func open(for workspace: CameraWorkspace) -> String? {
        guard !workspace.cameras.isEmpty else { return "Add at least one camera to open a cluster shell." }
        guard let csshX = BundledTools.csshXURL else {
            return "The bundled csshX tool is missing. Reinstall Camera Stream from the DMG."
        }

        let username = workspace.cameras.first?.username ?? "pi"
        guard isSafeSSHIdentifier(username) else { return "The camera username contains unsupported characters." }
        let hosts = workspace.cameras.map(\.host)
        guard hosts.allSatisfy(isSafeSSHHost) else { return "One or more camera hosts contain unsupported characters." }

        let command = ([csshX.path, username] + hosts)
            .map(shellEscape)
            .joined(separator: " ")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "tell application \"Terminal\" to activate",
            "-e", "tell application \"Terminal\" to do script \"\(command)\""
        ]
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return "Could not open Terminal (exit status \(process.terminationStatus))."
            }
        } catch {
            return "Could not open Terminal: \(error.localizedDescription)"
        }
        return nil
    }

    private static func isSafeSSHIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
    }

    private static func isSafeSSHHost(_ value: String) -> Bool {
        !value.isEmpty && value.range(of: #"^[A-Za-z0-9._:-]+$"#, options: .regularExpression) != nil
    }

    private static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
