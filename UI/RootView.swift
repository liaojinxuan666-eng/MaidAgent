import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            ChatView()
                .tabItem { Label("会话", systemImage: "message.fill") }
            
            HubView()
                .tabItem { Label("探索", systemImage: "square.grid.2x2.fill") }
            
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        .tint(.white)
    }
}