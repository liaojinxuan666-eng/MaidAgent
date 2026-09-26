import Foundation

class ProjectStore: ObservableObject {
    static let shared = ProjectStore()
    @Published var projects: [Project] = []
    
    private let storeURL: URL
    
    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.storeURL = docs.appendingPathComponent("projects.json")
        load()
    }
    
    func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let loaded = try? JSONDecoder().decode([Project].self, from: data) else {
            return
        }
        projects = loaded
    }
    
    func save() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
    
    func createProject(name: String) -> Project {
        let project = Project(name: name)
        projects.append(project)
        save()
        return project
    }
    
    func deleteProject(_ id: UUID) {
        projects.removeAll { $0.id == id }
        save()
    }
    
    func getProject(_ id: UUID) -> Project? {
        projects.first { $0.id == id }
    }
    
    func updateProject(_ project: Project) {
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            var updated = project
            updated.modifiedAt = Date()
            projects[idx] = updated
            save()
        }
    }
    
    /// 创建新会话
    func createSession(projectId: UUID, title: String) -> ChatSession? {
        guard let idx = projects.firstIndex(where: { $0.id == projectId }) else { return nil }
        let session = ChatSession(title: title.isEmpty ? "新会话" : title)
        projects[idx].sessions.append(session)
        projects[idx].modifiedAt = Date()
        save()
        return session
    }
    
    /// 更新某个会话的消息
    func updateSessionMessages(projectId: UUID, sessionId: UUID, messages: [ChatMessage]) {
        guard let pIdx = projects.firstIndex(where: { $0.id == projectId }),
              let sIdx = projects[pIdx].sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        projects[pIdx].sessions[sIdx].messages = messages
        projects[pIdx].sessions[sIdx].modifiedAt = Date()
        projects[pIdx].modifiedAt = Date()
        save()
    }
    
    /// 获取某个会话
    func getSession(projectId: UUID, sessionId: UUID) -> ChatSession? {
        guard let project = getProject(projectId) else { return nil }
        return project.sessions.first { $0.id == sessionId }
    }
}