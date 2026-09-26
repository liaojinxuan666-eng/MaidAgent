import Foundation

// MARK: - 读文件
struct ReadFileTool: AITool {
    static let name = "read_file"
    static let description = "读取沙箱内指定文件的完整内容"
    static let parameters: [String: Any] = [
        "type": "object",
        "properties": [
            "path": ["type": "string", "description": "文件路径，相对根目录"]
        ],
        "required": ["path"]
    ]
    
    static func execute(arguments: [String: Any]) async throws -> String {
        guard let path = arguments["path"] as? String else {
            return "错误：缺少 path 参数"
        }
        do {
            return try VirtualFileSystem.shared.readFile(path)
        } catch {
            return "读取失败: \(error.localizedDescription)"
        }
    }
}

// MARK: - 写文件
struct WriteFileTool: AITool {
    static let name = "write_file"
    static let description = "将内容写入沙箱内的指定文件，会覆盖原内容"
    static let parameters: [String: Any] = [
        "type": "object",
        "properties": [
            "path": ["type": "string", "description": "文件路径，相对根目录"],
            "content": ["type": "string", "description": "完整的文件内容"]
        ],
        "required": ["path", "content"]
    ]
    
    static func execute(arguments: [String: Any]) async throws -> String {
        guard let path = arguments["path"] as? String,
              let content = arguments["content"] as? String else {
            return "错误：参数不完整"
        }
        do {
            try VirtualFileSystem.shared.writeFile(path, content: content)
            return "成功写入 \(path)"
        } catch {
            return "写入失败: \(error.localizedDescription)"
        }
    }
}

// MARK: - 列出目录
struct ListDirTool: AITool {
    static let name = "list_dir"
    static let description = "列出沙箱内指定目录下的所有文件和子目录"
    static let parameters: [String: Any] = [
        "type": "object",
        "properties": [
            "path": ["type": "string", "description": "目录路径，根目录传空字符串"]
        ],
        "required": ["path"]
    ]
    
    static func execute(arguments: [String: Any]) async throws -> String {
        let path = arguments["path"] as? String ?? ""
        do {
            let items = try VirtualFileSystem.shared.listDir(path)
            return items.isEmpty ? "(空目录)" : items.joined(separator: "\n")
        } catch {
            return "读取目录失败: \(error.localizedDescription)"
        }
    }
}

// MARK: - 执行终端命令
struct ExecuteCommandTool: AITool {
    static let name = "execute_command"
    static let description = "在沙箱虚拟终端中执行命令。支持 ls, cat, mkdir, touch, rm, echo, grep, find, wc, head, tail 等。禁止使用 sudo, su 等越权命令。"
    static let parameters: [String: Any] = [
        "type": "object",
        "properties": [
            "command": ["type": "string", "description": "要执行的完整命令，例如 'ls /src' 或 'cat main.swift'"]
        ],
        "required": ["command"]
    ]
    
    static func execute(arguments: [String: Any]) async throws -> String {
        guard let command = arguments["command"] as? String else {
            return "错误：缺少 command 参数"
        }
        
        let result = try await CommandInterpreter.shared.execute(command)
        
        // 把标准输出和退出码一并返回，让 AI 知道执行结果
        let status = result.exitCode == 0 ? "✅" : "❌"
        return "\(status) 执行结果:\n\(result.output)"
    }
}