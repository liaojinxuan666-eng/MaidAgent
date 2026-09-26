import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    var id: UUID = UUID() // 必须是 var
    let role: String
    var content: String   // 必须是 var，流式输出需要修改它
    var type: String = "text"
    var toolName: String? = nil
    var toolArgs: String? = nil
    
    // 必须包含带 id 参数的初始化方法
    init(id: UUID = UUID(), role: String, content: String, type: String = "text", toolName: String? = nil, toolArgs: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.type = type
        self.toolName = toolName
        self.toolArgs = toolArgs
    }
}