import AppKit
import Foundation

@MainActor
final class StreamController: ObservableObject {
    @Published var status = "Ready"
    @Published var isStreaming = false
    @Published var streamEndpoints: [StreamEndpoint] = []
    private var tunnels: [Process] = []
    private var activeWorkspace: CameraWorkspace?
    private var credentialFile: URL?
    private var cameraSettings: [UUID: CaptureSettings] = [:]
    private let logURL: URL = {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CameraStream", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("streaming.log")
    }()

    func start(_ workspace: CameraWorkspace) {
        let cameras = workspace.cameras
        guard !cameras.isEmpty else { return }
        stop()
        activeWorkspace = workspace
        cameraSettings = Dictionary(uniqueKeysWithValues: cameras.map { ($0.id, ($0.settings ?? .default).clamped()) })
        credentialFile = SessionCredentials.create(cameras: cameras, jumpHost: workspace.jumpHost, passwords: CredentialStore.shared.passwords)
        isStreaming = true
        status = "Starting \(cameras.count) camera streams…"
        Task { @MainActor in
            for (index, camera) in cameras.enumerated() { await launch(camera, index: index, jumpHost: workspace.jumpHost) }
            try? await Task.sleep(for: .seconds(3))
            guard isStreaming else { return }
            if let jumpHost = workspace.jumpHost, !jumpHost.isEmpty {
                for (index, camera) in cameras.enumerated() { openTunnel(to: camera, remotePort: 8888 + index, localPort: 18_000 + index, jumpHost: jumpHost) }
                try? await Task.sleep(for: .milliseconds(500))
                streamEndpoints = cameras.enumerated().map { StreamEndpoint(id: $0.element.id, name: $0.element.name, host: "127.0.0.1", port: 18_000 + $0.offset) }
            } else {
                streamEndpoints = cameras.enumerated().map { StreamEndpoint(id: $0.element.id, name: $0.element.name, host: $0.element.host, port: 8888 + $0.offset) }
            }
            await resolveCameraNames(cameras, jumpHost: workspace.jumpHost, credentialFile: credentialFile)
            status = "Streaming \(cameras.count) cameras"
        }
    }

    func stop() {
        streamEndpoints.removeAll()
        tunnels.forEach { $0.terminate() }
        tunnels.removeAll()
        let workspace = activeWorkspace
        let cameras = workspace?.cameras ?? []
        let closingCredentialFile = credentialFile
        activeWorkspace = nil
        credentialFile = nil
        cameraSettings.removeAll()
        isStreaming = false
        guard !cameras.isEmpty else { status = "Ready"; return }
        status = "Stopping camera encoders…"
        for camera in cameras { runSSH(camera, jumpHost: workspace?.jumpHost, credentialFile: closingCredentialFile, command: "pkill -x libcamera-vid 2>/dev/null; pkill -x rpicam-vid 2>/dev/null; pkill -x raspivid 2>/dev/null; true") }
        if let closingCredentialFile {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(8))
                try? FileManager.default.removeItem(at: closingCredentialFile)
            }
        }
        status = "Stopped"
    }

    /// Current capture settings for a camera, falling back to defaults.
    func settings(for cameraID: UUID) -> CaptureSettings { cameraSettings[cameraID] ?? .default }

    /// Relaunch a single camera's encoder with new capture settings and force
    /// its player to reconnect. The Pi camera stack has no live control channel,
    /// so this kills and restarts only that camera's encoder.
    func applySettings(cameraID: UUID, settings newSettings: CaptureSettings) {
        guard isStreaming,
              let workspace = activeWorkspace,
              let index = workspace.cameras.firstIndex(where: { $0.id == cameraID }) else { return }
        let camera = workspace.cameras[index]
        let sanitized = newSettings.clamped()
        cameraSettings[cameraID] = sanitized
        status = "Applying capture settings to \(camera.name)…"
        runSSH(camera, jumpHost: workspace.jumpHost, credentialFile: credentialFile, command: launchCommand(port: 8888 + index, settings: sanitized))
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard isStreaming else { return }
            if let endpointIndex = streamEndpoints.firstIndex(where: { $0.id == cameraID }) {
                streamEndpoints[endpointIndex].revision += 1
            }
            status = "Applied capture settings to \(camera.name)"
        }
    }

    private func launch(_ camera: CameraEndpoint, index: Int, jumpHost: String?) async {
        let settings = cameraSettings[camera.id] ?? .default
        runSSH(camera, jumpHost: jumpHost, credentialFile: credentialFile, command: launchCommand(port: 8888 + index, settings: settings))
    }

    private func launchCommand(port: Int, settings: CaptureSettings) -> String {
        """
        pkill -x libcamera-vid 2>/dev/null || true; pkill -x rpicam-vid 2>/dev/null || true; pkill -x raspivid 2>/dev/null || true;
        if command -v rpicam-vid >/dev/null 2>&1; then c=$(command -v rpicam-vid); elif command -v libcamera-vid >/dev/null 2>&1; then c=$(command -v libcamera-vid); elif command -v raspivid >/dev/null 2>&1; then c=$(command -v raspivid); else exit 127; fi;
        if [ "${c##*/}" = raspivid ]; then nohup "$c" \(settings.raspividArguments) -o tcp://0.0.0.0:\(port) -t 0 >/tmp/camera-stream.log 2>&1 & else nohup "$c" \(settings.libcameraArguments) -o tcp://0.0.0.0:\(port) -t 0 >/tmp/camera-stream.log 2>&1 & fi
        """
    }

    private func runSSH(_ camera: CameraEndpoint, jumpHost: String?, credentialFile: URL? = nil, command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        // Do not inherit ~/.ssh/config ControlMaster settings: reusable master
        // processes outlive the app and can retain a stale SSH_ASKPASS helper.
        var arguments = ["-F", "/dev/null", "-o", "ControlMaster=no", "-o", "ControlPersist=no", "-o", "ConnectTimeout=6", "-o", "StrictHostKeyChecking=accept-new"]
        if let jumpHost, !jumpHost.isEmpty { arguments += ["-J", jumpHost] }
        arguments += [camera.address, command]
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        if let askpass = askpassURL() {
            environment["SSH_ASKPASS"] = askpass.path
            environment["SSH_ASKPASS_REQUIRE"] = "force"
            environment["DISPLAY"] = "1"
            environment["CAMERA_STREAM_KEYCHAIN_ACCOUNT"] = camera.credentialAccount
            if let credentialFile { environment["CAMERA_STREAM_CREDENTIALS_FILE"] = credentialFile.path }
        }
        process.environment = environment
        launch(process, label: "ssh \(camera.address)")
    }

    private func openTunnel(to camera: CameraEndpoint, remotePort: Int, localPort: Int, jumpHost: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-F", "/dev/null", "-o", "ControlMaster=no", "-o", "ControlPersist=no", "-o", "ConnectTimeout=6", "-o", "ExitOnForwardFailure=yes", "-N", "-L", "\(localPort):\(camera.host):\(remotePort)", jumpHost]
        var environment = ProcessInfo.processInfo.environment
        if let askpass = askpassURL() {
            environment["SSH_ASKPASS"] = askpass.path
            environment["SSH_ASKPASS_REQUIRE"] = "force"
            environment["DISPLAY"] = "1"
            environment["CAMERA_STREAM_KEYCHAIN_ACCOUNT"] = jumpHost
            if let credentialFile { environment["CAMERA_STREAM_CREDENTIALS_FILE"] = credentialFile.path }
        }
        process.environment = environment
        launch(process, label: "tunnel \(localPort) → \(camera.host):\(remotePort) via \(jumpHost)")
        tunnels.append(process)
    }

    private func resolveCameraNames(_ cameras: [CameraEndpoint], jumpHost: String?, credentialFile: URL?) async {
        await withTaskGroup(of: (UUID, String).self) { group in
            for camera in cameras {
                group.addTask { [weak self] in
                    let name = await self?.fetchCameraName(camera, jumpHost: jumpHost, credentialFile: credentialFile) ?? camera.name
                    return (camera.id, name)
                }
            }
            for await (id, name) in group {
                if let index = streamEndpoints.firstIndex(where: { $0.id == id }) { streamEndpoints[index].name = name }
            }
        }
    }

    nonisolated private func fetchCameraName(_ camera: CameraEndpoint, jumpHost: String?, credentialFile: URL?) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            var arguments = ["-F", "/dev/null", "-o", "ControlMaster=no", "-o", "ControlPersist=no", "-o", "ConnectTimeout=5", "-o", "StrictHostKeyChecking=accept-new"]
            if let jumpHost, !jumpHost.isEmpty { arguments += ["-J", jumpHost] }
            arguments += [camera.address, "boxid=$(printenv BOXID 2>/dev/null || true); if [ -n \"$boxid\" ]; then printf '%s' \"$boxid\"; else hostname; fi"]
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = Pipe()
            var environment = ProcessInfo.processInfo.environment
            if let askpass = Self.askpassURLStatic(), let credentialFile {
                environment["SSH_ASKPASS"] = askpass.path
                environment["SSH_ASKPASS_REQUIRE"] = "force"
                environment["DISPLAY"] = "1"
                environment["CAMERA_STREAM_KEYCHAIN_ACCOUNT"] = camera.credentialAccount
                environment["CAMERA_STREAM_CREDENTIALS_FILE"] = credentialFile.path
                process.terminationHandler = { _ in
                    let value = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: value?.isEmpty == false ? value : nil)
                }
            } else {
                process.terminationHandler = { _ in
                    let value = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: value?.isEmpty == false ? value : nil)
                }
            }
            process.environment = environment
            do { try process.run() } catch { continuation.resume(returning: nil) }
        }
    }

    nonisolated private static func askpassURLStatic() -> URL? {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        let bundled = executable.deletingLastPathComponent().appendingPathComponent("CameraSSHAskpass")
        return FileManager.default.isExecutableFile(atPath: bundled.path) ? bundled : nil
    }

    private func askpassURL() -> URL? {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        let bundled = executable.deletingLastPathComponent().appendingPathComponent("CameraSSHAskpass")
        return FileManager.default.isExecutableFile(atPath: bundled.path) ? bundled : nil
    }

    private func launch(_ process: Process, label: String) {
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.writeLog("[\(label)] \(text)") }
        }
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in self?.writeLog("[\(label)] exited with status \(process.terminationStatus)") }
        }
        do { try process.run() }
        catch { writeLog("[\(label)] could not start: \(error.localizedDescription)") }
    }

    private func writeLog(_ message: String) {
        let entry = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        if let data = entry.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path), let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                try? handle.seekToEnd(); try? handle.write(contentsOf: data)
            } else { try? data.write(to: logURL, options: .atomic) }
        }
    }
}
