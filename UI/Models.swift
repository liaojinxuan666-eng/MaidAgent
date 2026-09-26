import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: String
    let content: String
    
    init(role: String, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
    }
}

struct ProjectFile: Identifiable {
    let id = UUID()
    let name: String
    let isDirectory: Bool
    let children: [ProjectFile]?
}
