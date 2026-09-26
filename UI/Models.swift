import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: String
    let content: String
    var type: String = "text" // "text", "tool_call", "thinking"
    var toolName: String? = nil
    var toolArgs: String? = nil
    
    init(role: String, content: String, type: String = "text", toolName: String? = nil, toolArgs: String? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.type = type
        self.toolName = toolName
        self.toolArgs = toolArgs
    }
}