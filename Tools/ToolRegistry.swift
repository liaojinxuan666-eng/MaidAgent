import Foundation

/// 所有工具都必须实现这个协议
protocol AITool {
    static var name: String { get }
    static var description: String { get }
    static var parameters: [String: Any] { get }
    static func execute(arguments: [String: Any]) async throws -> String
}

final class ToolRegistry {
    static let shared = ToolRegistry()
    
    private var tools: [String: AITool.Type] = [:]
    
    private init() {
        // 在这里注册所有工具
        register(ReadFileTool.self)
        register(WriteFileTool.self)
        register(ListDirTool.self)
        register(ExecuteCommandTool.self)
    }
    
    func register(_ tool: AITool.Type) {
        tools[tool.name] = tool
    }
    
    /// 生成给 API 用的 tools schema（OpenAI 格式）
    func apiSchema() -> [[String: Any]] {
        return tools.values.map { tool in
            [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": tool.parameters
                ]
            ]
        }
    }
    
    /// AI 触发工具调用时执行
    func execute(name: String, arguments: [String: Any]) async throws -> String {
        guard let tool = tools[name] else {
            return "错误：未知工具 \(name)"
        }
        return try await tool.execute(arguments: arguments)
    }
}