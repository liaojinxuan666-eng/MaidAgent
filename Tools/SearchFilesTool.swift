import Foundation

struct SearchFilesTool: AITool {
    static let name = "search_files"
    static let description = "在沙箱中按文件名或内容搜索。返回匹配的文件路径、行号和内容"
    static let parameters: [String: Any] = [
        "type": "object",
        "properties": [
            "query": ["type": "string", "description": "搜索关键词"],
            "path": ["type": "string", "description": "搜索起始目录，留空则全盘搜索"]
        ],
        "required": ["query"]
    ]

    static func execute(arguments: [String: Any]) async throws -> String {
        guard let query = arguments["query"] as? String else {
            return "缺少 query"
        }

        do {
            let vfs = VirtualFileSystem.shared
            var lines: [String] = []

            // 1. 文件名匹配
            let allPaths = vfs.allFilePaths()
            let nameMatches = allPaths.filter { $0.localizedCaseInsensitiveContains(query) }
            for p in nameMatches {
                lines.append("📄 \(p)")
            }

            // 2. 内容匹配
            let contentMatches = try vfs.search(query)
            for m in contentMatches.prefix(50) {
                lines.append("\(m.path):\(m.line): \(m.content.trimmingCharacters(in: .whitespaces))")
            }

            if lines.isEmpty {
                return "未找到匹配「\(query)」的文件"
            }
            return lines.joined(separator: "\n")
        } catch {
            return "搜索失败：\(error.localizedDescription)"
        }
    }
}