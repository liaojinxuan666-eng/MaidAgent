import Foundation

struct Project: Identifiable, Codable {
    let id: UUID
    var name: String
    var sessions: [ChatSession]
    var createdAt: Date
    var modifiedAt: Date
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.sessions = []
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

struct ChatSession: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var createdAt: Date
    var modifiedAt: Date
    
    init(title: String = "新会话") {
        self.id = UUID()
        self.title = title
        self.messages = []
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}