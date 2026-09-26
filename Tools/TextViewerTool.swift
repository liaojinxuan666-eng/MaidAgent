import Foundation

struct ViewTextTool: AITool {
    static let name = "view_text"
    static let description = "查看文本文件的指定行范围（分页读取，避免一次性拉太长）"
    static let parameters: [String: Any] = [
        "type": "object",
        "properties": [
            "path": ["type": "string", "description": "文件路径"],
            "start_line": ["type": "integer", "description": "起始行号（从 1 开始）"],
            "end_line": ["type": "integer", "description": "结束行号，包含"]
        ],
        "required": ["path", "start_line", "end_line"]
    ]

    static func execute(arguments: [String: Any]) async throws -> String {
        guard let path = arguments["path"] as? String,
              let start = arguments["start_line"] as? Int,
              let end = arguments["end_line"] as? Int else {
            return "参数不完整：需要 path / start_line / end_line"
        }

        do {
            let text = try VirtualFileSystem.shared.readFileText(path)
            let lines = text.components(separatedBy: .newlines)
            let s = max(0, start - 1)
            let e = min(lines.count, end)
            guard s < e else { return "行号范围无效（文件共 \(lines.count) 行）" }

            var result = "文件共 \(lines.count) 行，显示 \(s + 1) - \(e)：\n"
            for i in s..<e {
                result += "\(i + 1)\t\(lines[i])\n"
            }
            return result
        } catch {
            return "读取失败：\(error.localizedDescription)"
        }
    }
}