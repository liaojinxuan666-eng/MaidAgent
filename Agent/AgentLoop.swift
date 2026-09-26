import Foundation

final class AgentLoop {
    static let shared = AgentLoop()
    private init() {}
    private let maxIterations = 15
    
    @MainActor
    func run(
        initialMessages: [ChatMessage],
        onToken: @escaping (String) -> Void // 👈 新增：每次收到字就回调
    ) async throws -> [ChatMessage] {
        var messages = initialMessages
        var apiMessages: [[String: Any]] = [["role": "system", "content": systemPrompt]]
        apiMessages.append(contentsOf: messages.map { ["role": $0.role, "content": $0.content] })
        
        var iteration = 0
        while iteration < maxIterations {
            iteration += 1
            let toolsSchema = ToolRegistry.shared.apiSchema()
            
            var fullContent = ""
            
            // 流式接收
            for try await token in APIClient.shared.chatStream(messages: apiMessages, tools: toolsSchema) {
                fullContent += token
                onToken(token) // 通知 UI 刷新
            }
            
            // 如果 AI 返回了工具调用，需要重新发起一次非流式请求专门拿工具信息（为了简化，暂时略过复杂的流式工具解析）
            // 这里提供一个简化版：如果有文本，直接返回文本
            if !fullContent.isEmpty {
                messages.append(ChatMessage(role: "assistant", content: fullContent))
                return messages
            }
            
            // 如果流式没拿到内容，可能是在调用工具，直接报错退出（第一版限制）
            messages.append(ChatMessage(role: "assistant", content: "（本次回复未生成文本，可能触发了工具调用，请查看日志）"))
            return messages
        }
        messages.append(ChatMessage(role: "assistant", content: "⚠️ 超过最大循环次数。"))
        return messages
    }
    
    private var systemPrompt: String {
        """
        你是 PocketCode，运行在 iOS 上的编程 AI Agent。
        你可以使用工具读写文件、执行命令。
        当用户要求写代码时，请直接输出代码块。
        """
    }
}