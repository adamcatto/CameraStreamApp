import Foundation

/// Per-camera encoder capture settings. The Raspberry Pi camera stack only
/// accepts these as launch arguments, so changing them means relaunching the
/// camera's encoder (see StreamController.applySettings). Defaults reproduce the
/// original hardcoded pipeline.
struct CaptureSettings: Codable, Hashable {
    var shutterMicroseconds: Int = 20000
    var gain: Double = 32
    var brightness: Double = 0.2
    var contrast: Double = 1
    var saturation: Double = 1
    var sharpness: Double = 1
    var ev: Double = 0
    var framerate: Int = 30

    static let `default` = CaptureSettings()

    func clamped() -> CaptureSettings {
        var value = self
        value.shutterMicroseconds = min(200_000, max(0, shutterMicroseconds))
        value.gain = min(64, max(1, gain))
        value.brightness = min(1, max(-1, brightness))
        value.contrast = min(2, max(0, contrast))
        value.saturation = min(2, max(0, saturation))
        value.sharpness = min(2, max(0, sharpness))
        value.ev = min(10, max(-10, ev))
        value.framerate = min(120, max(1, framerate))
        return value
    }

    /// Compact, locale-independent number formatting for shell arguments.
    private func format(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%g", value)
    }

    /// rpicam-vid / libcamera-vid capture arguments (excluding output).
    var libcameraArguments: String {
        let settings = clamped()
        var parts: [String] = []
        if settings.shutterMicroseconds > 0 { parts.append("--shutter \(settings.shutterMicroseconds)") }
        parts.append("--gain \(format(settings.gain))")
        parts.append("--brightness \(format(settings.brightness))")
        parts.append("--contrast \(format(settings.contrast))")
        parts.append("--saturation \(format(settings.saturation))")
        parts.append("--sharpness \(format(settings.sharpness))")
        parts.append("--ev \(format(settings.ev))")
        parts.append("--width 1920 --height 1080 --codec h264")
        parts.append("--framerate \(settings.framerate)")
        parts.append("--autofocus-mode auto --lens-position 3 --inline --listen")
        return parts.joined(separator: " ")
    }

    /// Legacy raspivid capture arguments (excluding output), mapped from the
    /// libcamera-centric scales onto raspivid's ranges.
    var raspividArguments: String {
        let settings = clamped()
        func clampInt(_ value: Double, _ low: Int, _ high: Int) -> Int { min(high, max(low, Int(value.rounded()))) }
        var parts = ["-md 4"]
        if settings.shutterMicroseconds > 0 { parts.append("-ss \(settings.shutterMicroseconds)") }
        parts.append("-ISO \(clampInt(settings.gain, 0, 1600))")
        parts.append("-w 1640 -h 1232")
        parts.append("-fps \(settings.framerate)")
        parts.append("-br \(clampInt((settings.brightness + 1) * 50, 0, 100))")
        parts.append("-co \(clampInt((settings.contrast - 1) * 100, -100, 100))")
        parts.append("-sa \(clampInt((settings.saturation - 1) * 100, -100, 100))")
        parts.append("-sh \(clampInt((settings.sharpness - 1) * 100, -100, 100))")
        parts.append("-ev \(clampInt(settings.ev, -10, 10))")
        parts.append("-ih -n -l")
        return parts.joined(separator: " ")
    }
}

struct CameraEndpoint: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var host: String
    var username: String = "pi"
    var port: Int = 8888
    var settings: CaptureSettings? = nil

    var address: String { "\(username)@\(host)" }
    var credentialAccount: String { "\(username)@\(host)" }
}

struct CameraWorkspace: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var cameras: [CameraEndpoint]
    var jumpHost: String? = nil

    static let example = CameraWorkspace(
        name: "Example workspace",
        cameras: [CameraEndpoint(name: "Camera 1", host: "192.0.2.10")],
        jumpHost: nil
    )
}

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var workspaces: [CameraWorkspace] { didSet { save() } }
    @Published var selectedID: UUID?
    private let fileURL: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CameraStream", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("workspaces.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([CameraWorkspace].self, from: data), !saved.isEmpty {
            workspaces = saved
        } else if let bundled = Self.bundledProfilesWorkspaces() {
            workspaces = bundled
            save()
        } else {
            workspaces = [.example]
        }
        selectedID = workspaces.first?.id
    }

    private static func bundledProfilesWorkspaces() -> [CameraWorkspace]? {
        guard let url = Bundle.main.url(forResource: "profiles-workspaces", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let workspaces = try? JSONDecoder().decode([CameraWorkspace].self, from: data),
              !workspaces.isEmpty else { return nil }
        return workspaces
    }

    var selectedIndex: Int? { workspaces.firstIndex { $0.id == selectedID } }
    func save() { if let data = try? JSONEncoder().encode(workspaces) { try? data.write(to: fileURL, options: .atomic) } }
}

@MainActor
final class CredentialStore: ObservableObject {
    static let shared = CredentialStore()
    @Published var passwords: [String: String] = [:]
    private init() {
        if let bundled = Self.bundledProfilesCredentials() {
            passwords = bundled
        }
    }

    private static func bundledProfilesCredentials() -> [String: String]? {
        guard let url = Bundle.main.url(forResource: "profiles-credentials", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let credentials = try? JSONDecoder().decode([String: String].self, from: data),
              !credentials.isEmpty else { return nil }
        return credentials
    }

    func accounts(for workspace: CameraWorkspace) -> [String] {
        workspace.cameras.map(\.credentialAccount) + (workspace.jumpHost.map { [$0] } ?? [])
    }
    func missingAccounts(for workspace: CameraWorkspace) -> [String] { accounts(for: workspace).filter { passwords[$0]?.isEmpty != false } }
    func clear() { passwords.removeAll() }
}

enum SessionCredentials {
    static func create(cameras: [CameraEndpoint], jumpHost: String?, passwords: [String: String]) -> URL? {
        var credentials: [String: String] = [:]
        for camera in cameras {
            if let password = passwords[camera.credentialAccount] { credentials[camera.credentialAccount] = password }
        }
        if let jumpHost, let password = passwords[jumpHost] { credentials[jumpHost] = password }
        guard !credentials.isEmpty,
              let data = try? JSONEncoder().encode(credentials) else { return nil }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("camera-stream-\(UUID().uuidString).json")
        do {
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            return file
        } catch { return nil }
    }
}
