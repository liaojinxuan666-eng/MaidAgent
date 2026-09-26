import SwiftUI

struct ProjectDetailView: View {
    let projectId: UUID
    @StateObject private var store = ProjectStore.shared
    @State private var showNewSession = false
    @State private var newSessionTitle = ""
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let project = store.getProject(projectId) {
                if project.sessions.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(project.sessions) { session in
                                NavigationLink(destination: ChatView(projectId: projectId, sessionId: session.id)) {
                                    SessionRow(session: session)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .navigationTitle(store.getProject(projectId)?.name ?? "项目")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showNewSession = true }) {
                    Image(systemName: "square.and.pencil").foregroundColor(.primary)
                }
            }
        }
        .sheet(isPresented: $showNewSession) {
            NewSessionSheet(
                isPresented: $showNewSession,
                title: $newSessionTitle,
                onCreate: {
                    _ = store.createSession(projectId: projectId, title: newSessionTitle)
                    newSessionTitle = ""
                }
            )
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            Text("还没有会话")
                .font(.headline)
                .foregroundColor(.primary)
            Text("点击右上角开始新的对话")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

struct SessionRow: View {
    let session: ChatSession
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 16))
                .foregroundColor(.blue)
                .frame(width: 40, height: 40)
                .background(Color.blue.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text("\(session.messages.count) 条消息")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct NewSessionSheet: View {
    @Binding var isPresented: Bool
    @Binding var title: String
    var onCreate: () -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("会话标题")) {
                    TextField("例如：修复渲染管线", text: $title)
                }
            }
            .navigationTitle("新建会话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("创建") {
                        onCreate()
                        isPresented = false
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}