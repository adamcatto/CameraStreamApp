import SwiftUI

@main
struct CameraStreamApp: App {
    @StateObject private var store = WorkspaceStore()
    @StateObject private var streamer = StreamController()

    var body: some Scene {
        WindowGroup("Camera Stream") {
            ContentView()
                .environmentObject(store)
                .environmentObject(streamer)
                .frame(minWidth: 820, minHeight: 520)
        }
    }
}
