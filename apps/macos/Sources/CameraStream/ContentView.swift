import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var streamer: StreamController
    @StateObject private var credentials = CredentialStore.shared
    @State private var showSettings = false
    @State private var pendingWorkspace: CameraWorkspace?
    @State private var clusterShellError: String?
    @State private var renamingWorkspaceID: UUID?
    @State private var renameText = ""
    @State private var deletingWorkspace: CameraWorkspace?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $store.selectedID) {
                    ForEach(store.workspaces) { workspace in
                        Text(workspace.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .tag(workspace.id)
                    }
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    if let id = ids.first,
                       let workspace = store.workspaces.first(where: { $0.id == id }) {
                        Button("Rename…") { beginRename(workspace) }
                        Button("Delete Workspace", role: .destructive) { deletingWorkspace = workspace }
                    }
                }
                .onChange(of: store.selectedID) { _, _ in showSettings = false }
                .frame(minHeight: 0, maxHeight: .infinity)

                sidebarSettingsButton
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: addWorkspace) {
                        Image(systemName: "plus")
                    }
                    .help("Add workspace")
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            if showSettings {
                SettingsView(credentials: credentials)
            } else if let index = store.selectedIndex {
                VStack(spacing: 0) {
                    HStack {
                        Text(store.workspaces[index].name).font(.title2)
                        Spacer()
                        Button("Open cluster shell") { openClusterShell(store.workspaces[index]) }
                        Button("Start streaming") { requestStart(store.workspaces[index]) }.disabled(streamer.isStreaming)
                        Button("Stop", role: .destructive) { streamer.stop() }.disabled(!streamer.isStreaming)
                    }.padding()
                    if streamer.isStreaming { StreamGrid(endpoints: streamer.streamEndpoints) }
                    else {
                        WorkspaceEditor(workspace: $store.workspaces[index])
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            } else { ContentUnavailableView("Select a workspace", systemImage: "video") }
        }
        .safeAreaInset(edge: .bottom) { Text(streamer.status).frame(maxWidth: .infinity, alignment: .leading).padding(8).background(.bar) }
        .sheet(item: $pendingWorkspace) { WorkspacePasswordPrompt(workspace: $0, credentials: credentials) { workspace in streamer.start(workspace) } }
        .alert("Cluster shell", isPresented: Binding(get: { clusterShellError != nil }, set: { if !$0 { clusterShellError = nil } })) {
            Button("OK", role: .cancel) { clusterShellError = nil }
        } message: { Text(clusterShellError ?? "") }
        .alert("Rename workspace", isPresented: Binding(
            get: { renamingWorkspaceID != nil },
            set: { if !$0 { renamingWorkspaceID = nil } }
        )) {
            TextField("Workspace name", text: $renameText)
            Button("Rename") { applyRename() }
                .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { renamingWorkspaceID = nil }
        } message: {
            Text("Enter a new name for this workspace.")
        }
        .alert("Delete workspace?", isPresented: Binding(
            get: { deletingWorkspace != nil },
            set: { if !$0 { deletingWorkspace = nil } }
        )) {
            Button("Delete Workspace", role: .destructive) {
                if let workspace = deletingWorkspace {
                    deleteWorkspace(workspace)
                }
                deletingWorkspace = nil
            }
            Button("Cancel", role: .cancel) { deletingWorkspace = nil }
        } message: {
            if let workspace = deletingWorkspace {
                Text("Are you sure you want to delete \"\(workspace.name)\"? This cannot be undone.")
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { showSettings = true }) {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in streamer.stop() }
    }

    private var sidebarSettingsButton: some View {
        VStack(spacing: 0) {
            Divider()
            Button(action: { showSettings = true }) {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(10)
            .background(showSettings ? Color.accentColor.opacity(0.15) : Color.clear)
            .help("Settings")
        }
        .background(.bar)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func openClusterShell(_ workspace: CameraWorkspace) {
        if let error = ClusterShell.open(for: workspace) { clusterShellError = error }
    }

    private func requestStart(_ workspace: CameraWorkspace) {
        if credentials.missingAccounts(for: workspace).isEmpty { streamer.start(workspace) }
        else { pendingWorkspace = workspace }
    }
    private func addWorkspace() { let workspace = CameraWorkspace(name: "New workspace", cameras: []); store.workspaces.append(workspace); store.selectedID = workspace.id }

    private func beginRename(_ workspace: CameraWorkspace) {
        renamingWorkspaceID = workspace.id
        renameText = workspace.name
    }

    private func applyRename() {
        guard let id = renamingWorkspaceID,
              let index = store.workspaces.firstIndex(where: { $0.id == id }) else {
            renamingWorkspaceID = nil
            return
        }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.workspaces[index].name = trimmed
        renamingWorkspaceID = nil
    }

    private func deleteWorkspace(_ workspace: CameraWorkspace) {
        guard let index = store.workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        let wasSelected = store.selectedID == workspace.id
        store.workspaces.remove(at: index)
        if wasSelected {
            store.selectedID = store.workspaces.first?.id
            showSettings = false
        }
    }
}

private struct WorkspacePasswordPrompt: View {
    let workspace: CameraWorkspace
    @ObservedObject var credentials: CredentialStore
    let start: (CameraWorkspace) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var cameraPassword = ""
    @State private var jumpPassword = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Credentials needed for \(workspace.name)").font(.title2)
            Text("Passwords are used only for this app session and are discarded when you quit.").foregroundStyle(.secondary)
            SecureField("Shared password for camera accounts", text: $cameraPassword)
            if let jumpHost = workspace.jumpHost { SecureField("Password for jump host \(jumpHost)", text: $jumpPassword) }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Start") { saveAndStart() }.keyboardShortcut(.defaultAction).disabled(cameraPassword.isEmpty || (workspace.jumpHost != nil && jumpPassword.isEmpty)) }
        }.padding(24).frame(width: 520)
    }
    private func saveAndStart() {
        for camera in workspace.cameras { credentials.passwords[camera.credentialAccount] = cameraPassword }
        if let jumpHost = workspace.jumpHost { credentials.passwords[jumpHost] = jumpPassword }
        dismiss(); start(workspace)
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @ObservedObject var credentials: CredentialStore
    @State private var revealedAccounts: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Settings").font(.title2)
                Text("Rename cameras and manage session credentials here. Passwords are not saved to Keychain or disk.").foregroundStyle(.secondary)
                Text("Bundled tools: \(BundledTools.bundledToolStatus)").font(.caption).foregroundStyle(.secondary)
            }.padding()
            List {
                ForEach(Array(store.workspaces.enumerated()), id: \.element.id) { workspaceIndex, workspace in
                    Section(workspace.name) {
                        ForEach($store.workspaces[workspaceIndex].cameras) { $camera in
                            SettingsCameraRow(
                                camera: $camera,
                                credentials: credentials,
                                revealedAccounts: $revealedAccounts
                            )
                        }
                        if let jumpHost = workspace.jumpHost {
                            SettingsCredentialRow(
                                label: "Jump host",
                                detail: jumpHost,
                                account: jumpHost,
                                credentials: credentials,
                                revealedAccounts: $revealedAccounts
                            )
                        }
                    }
                }
            }
            HStack {
                Button("Clear all session credentials", role: .destructive) { credentials.clear() }
                Spacer()
            }.padding()
        }
    }
}

private struct SettingsCameraRow: View {
    @Binding var camera: CameraEndpoint
    @ObservedObject var credentials: CredentialStore
    @Binding var revealedAccounts: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $camera.name)
                .textFieldStyle(.roundedBorder)
            SettingsCredentialRow(
                detail: camera.credentialAccount,
                account: camera.credentialAccount,
                credentials: credentials,
                revealedAccounts: $revealedAccounts
            )
        }
        .padding(.vertical, 4)
    }
}

private struct SettingsCredentialRow: View {
    var label: String? = nil
    let detail: String
    let account: String
    @ObservedObject var credentials: CredentialStore
    @Binding var revealedAccounts: Set<String>

    private var passwordBinding: Binding<String> {
        Binding(
            get: { credentials.passwords[account] ?? "" },
            set: { credentials.passwords[account] = $0 }
        )
    }

    private var isRevealed: Bool { revealedAccounts.contains(account) }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if let label {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                }
                Text(detail).font(label == nil ? .body : .caption2).foregroundStyle(label == nil ? .primary : .tertiary)
            }
            .frame(width: 180, alignment: .leading)
            Group {
                if isRevealed {
                    TextField("Password", text: passwordBinding)
                } else {
                    SecureField("Password", text: passwordBinding)
                }
            }
            .textFieldStyle(.roundedBorder)
            Button(action: { toggleReveal() }) {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .help(isRevealed ? "Hide password" : "Show password")
        }
    }

    private func toggleReveal() {
        if isRevealed { revealedAccounts.remove(account) }
        else { revealedAccounts.insert(account) }
    }
}

private struct StreamGrid: View {
    let endpoints: [StreamEndpoint]
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 10)], spacing: 10) {
                ForEach(endpoints) { endpoint in StreamTile(endpoint: endpoint) }
            }
            .padding()
        }
    }
}

private struct StreamTile: View {
    let endpoint: StreamEndpoint
    @EnvironmentObject private var streamer: StreamController
    @State private var showSettings = false
    @State private var draft = CaptureSettings.default

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                H264StreamView(endpoint: endpoint)
                    .id(endpoint.revision)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 6))
                Button {
                    draft = streamer.settings(for: endpoint.id)
                    showSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .padding(6)
                        .background(.black.opacity(0.45), in: Circle())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(6)
                .help("Adjust capture settings")
                .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                    CaptureSettingsForm(name: endpoint.name, settings: $draft) {
                        streamer.applySettings(cameraID: endpoint.id, settings: draft)
                        showSettings = false
                    } onReset: {
                        draft = .default
                    }
                }
            }
            Text("\(endpoint.name) · \(endpoint.host)").font(.caption).lineLimit(1)
        }
    }
}

private struct CaptureSettingsForm: View {
    let name: String
    @Binding var settings: CaptureSettings
    let onApply: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Capture settings · \(name)").font(.headline)
            sliderRow("Shutter (µs)",
                      value: Binding(get: { Double(settings.shutterMicroseconds) }, set: { settings.shutterMicroseconds = Int($0) }),
                      range: 0...200_000, step: 500,
                      display: settings.shutterMicroseconds == 0 ? "auto" : "\(settings.shutterMicroseconds)")
            sliderRow("Gain", value: $settings.gain, range: 1...64, step: 0.5)
            sliderRow("Brightness", value: $settings.brightness, range: -1...1, step: 0.05)
            sliderRow("Contrast", value: $settings.contrast, range: 0...2, step: 0.05)
            sliderRow("Saturation", value: $settings.saturation, range: 0...2, step: 0.05)
            sliderRow("Sharpness", value: $settings.sharpness, range: 0...2, step: 0.05)
            sliderRow("EV", value: $settings.ev, range: -10...10, step: 0.5)
            sliderRow("Frame rate",
                      value: Binding(get: { Double(settings.framerate) }, set: { settings.framerate = Int($0) }),
                      range: 1...120, step: 1,
                      display: "\(settings.framerate)")
            HStack {
                Button("Reset", action: onReset)
                Spacer()
                Button("Apply", action: onApply).keyboardShortcut(.defaultAction)
            }
            Text("Applying relaunches this camera's encoder, so its video reconnects briefly.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 320)
    }

    @ViewBuilder
    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, display: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text(display ?? String(format: "%.2f", value.wrappedValue))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
        }
    }
}

private struct WorkspaceEditor: View {
    @Binding var workspace: CameraWorkspace

    private let usernameColumnWidth: CGFloat = 90
    private let removeColumnWidth: CGFloat = 28

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Workspace name", text: $workspace.name)
                    .textFieldStyle(.roundedBorder)
                TextField("Jump host (optional, e.g. user@jump.example)", text: Binding(
                    get: { workspace.jumpHost ?? "" },
                    set: { workspace.jumpHost = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Cameras")
                        .font(.headline)

                    CameraListHeaderRow(usernameColumnWidth: usernameColumnWidth, removeColumnWidth: removeColumnWidth)

                    if workspace.cameras.isEmpty {
                        Text("No cameras yet.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach($workspace.cameras) { $camera in
                            CameraListRow(
                                camera: $camera,
                                usernameColumnWidth: usernameColumnWidth,
                                removeColumnWidth: removeColumnWidth
                            ) {
                                removeCamera(id: camera.id)
                            }
                        }
                    }

                    Button("Add camera") { addCamera() }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func addCamera() {
        workspace.cameras.append(CameraEndpoint(name: "Camera \(workspace.cameras.count + 1)", host: ""))
    }

    private func removeCamera(id: UUID) {
        workspace.cameras.removeAll { $0.id == id }
    }
}

private struct CameraListHeaderRow: View {
    let usernameColumnWidth: CGFloat
    let removeColumnWidth: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Text("Camera Name")
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("IP address")
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Username")
                .fontWeight(.bold)
                .frame(width: usernameColumnWidth, alignment: .leading)
            Color.clear.frame(width: removeColumnWidth)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct CameraListRow: View {
    @Binding var camera: CameraEndpoint
    let usernameColumnWidth: CGFloat
    let removeColumnWidth: CGFloat
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Camera name", text: $camera.name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
            TextField("IP address", text: $camera.host)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
            TextField("Username", text: $camera.username)
                .textFieldStyle(.roundedBorder)
                .frame(width: usernameColumnWidth)
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .frame(width: removeColumnWidth)
            .help("Remove camera")
        }
    }
}
