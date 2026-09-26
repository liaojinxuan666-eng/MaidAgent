import SwiftUI

struct ProjectView: View {
    @StateObject private var store = ProjectStore.shared
    @State private var showCreateSheet = false
    @State private var newProjectName = ""
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if store.projects.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.projects) { project in
                            NavigationLink(destination: ProjectDetailView(projectId: project.id)) {
                                ProjectRow(project: project)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("项目")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showCreateSheet = true }) {
                    Image(systemName: "plus").foregroundColor(.primary)
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateProjectSheet(
                isPresented: $showCreateSheet,
                name: $newProjectName,
                onCreate: {
                    _ = store.createProject(name: newProjectName)
                    newProjectName = ""
                }
            )
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            Text("创建你的第一个项目")
                .font(.headline)
                .foregroundColor(.primary)
            Text("每个项目有独立的 AI 上下文")
                .font(.caption)
                .foregroundColor(.gray)
            Button(action: { showCreateSheet = true }) {
                Text("新建项目")
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(Color.blue).foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .padding(.top, 8)
        }
    }
}

struct ProjectRow: View {
    let project: Project
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "folder.fill")
                .font(.system(size: 20)).foregroundColor(.blue)
                .frame(width: 44, height: 44)
                .background(Color.blue.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)
                Text("\(project.sessions.count) 个会话")
                    .font(.caption).foregroundColor(.gray)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption).foregroundColor(.gray)
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct CreateProjectSheet: View {
    @Binding var isPresented: Bool
    @Binding var name: String
    var onCreate: () -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("项目名称")) {
                    TextField("例如：PocketCode 开发", text: $name)
                }
            }
            .navigationTitle("新建项目")
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
                    .disabled(name.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}