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

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: addWorkspace) { Image(systemName: "plus") }.help("Add workspace")
                }.padding([.top, .horizontal], 8)
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
                    }
                }
                .onChange(of: store.selectedID) { _, _ in showSettings = false }
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
                    else { WorkspaceEditor(workspace: $store.workspaces[index]) }
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in streamer.stop() }
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
    var body: some View { ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 10)], spacing: 10) { ForEach(endpoints) { endpoint in VStack(spacing: 4) { H264StreamView(endpoint: endpoint).aspectRatio(16 / 9, contentMode: .fit).clipShape(.rect(cornerRadius: 6)); Text("\(endpoint.name) · \(endpoint.host)").font(.caption).lineLimit(1) } } }.padding() } }
}

private struct WorkspaceEditor: View {
    @Binding var workspace: CameraWorkspace
    @State private var selectedCamera: UUID?
    var body: some View {
        VStack(alignment: .leading) {
            TextField("Workspace name", text: $workspace.name).textFieldStyle(.roundedBorder).padding([.top, .horizontal])
            TextField("Jump host (optional, e.g. user@jump.example)", text: Binding(get: { workspace.jumpHost ?? "" }, set: { workspace.jumpHost = $0.isEmpty ? nil : $0 })).textFieldStyle(.roundedBorder).padding(.horizontal)
            List(selection: $selectedCamera) { ForEach($workspace.cameras) { $camera in HStack { TextField("Name", text: $camera.name); TextField("IP or hostname", text: $camera.host); TextField("User", text: $camera.username).frame(width: 70) }.tag(camera.id) }.onDelete { workspace.cameras.remove(atOffsets: $0) } }
            HStack { Button("Add camera") { workspace.cameras.append(CameraEndpoint(name: "Camera \(workspace.cameras.count + 1)", host: "")) }; Spacer() }.padding()
        }
    }
}
