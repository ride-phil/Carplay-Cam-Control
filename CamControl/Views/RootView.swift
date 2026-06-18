import SwiftUI

struct RootView: View {
    @StateObject private var manager = PairingManager()

    var body: some View {
        TabView {
            CamerasView(manager: manager)
                .tabItem {
                    Label("Cameras", systemImage: "video.fill")
                }

            ConnectView(manager: manager)
                .tabItem {
                    Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
    }
}
