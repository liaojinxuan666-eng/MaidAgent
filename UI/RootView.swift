import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            ChatView()
                .tabItem { Label("会话", systemImage: "message.fill") }
            
            // ✨ 加上项目标签页
            ProjectView()
                .tabItem { Label("项目", systemImage: "folder.fill") }
            
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        .tint(.white)
    }
}