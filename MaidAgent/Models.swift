import Foundation

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: String // "user" or "assistant"
    let content: String
}

struct ProjectFile: Identifiable {
    let id = UUID()
    let name: String
    let isDirectory: Bool
    let children: [ProjectFile]?
}