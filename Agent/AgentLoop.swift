import Foundation

final class AgentLoop {
    static let shared = AgentLoop()
    private init() {}
    private let maxIterations = 15
    
    @MainActor
    func run(
        initialMessages: [ChatMessage],
        onToken: @escaping (String) -> Void
    ) async throws -> [ChatMessage] {
        var messages = initialMessages
        var apiMessages: [[String: Any]] = [["role": "system", "content": systemPrompt]]
        apiMessages.append(contentsOf: messages.map { ["role": $0.role, "content": $0.content] })
        
        var iteration = 0
        while iteration < maxIterations {
            iteration += 1
            let toolsSchema = ToolRegistry.shared.apiSchema()
            
            var fullContent = ""
            var receivedToolCalls: [[String: Any]] = []
            
            for try await event in APIClient.shared.chatStream(messages: apiMessages, tools: toolsSchema) {
                switch event {
                case .text(let token):
                    fullContent += token
                    onToken(token)
                case .toolCalls(let calls):
                    receivedToolCalls = calls
                case .done:
                    break
                }
            }
            
            // 如果 AI 要调用工具
            if !receivedToolCalls.isEmpty {
                apiMessages.append(["role": "assistant", "content": fullContent, "tool_calls": receivedToolCalls])
                for call in receivedToolCalls {
                    guard let function = call["function"] as? [String: Any],
                          let toolName = function["name"] as? String,
                          let argsString = function["arguments"] as? String,
                          let toolCallId = call["id"] as? String else { continue }
                    
                    let argsData = argsString.data(using: .utf8) ?? Data()
                    let args = (try? JSONSerialization.jsonObject(with: argsData) as? [String: Any]) ?? [:]
                    
                    messages.append(ChatMessage(role: "assistant", content: "", type: "tool_call", toolName: toolName, toolArgs: argsString))
                    
                    let result = (try? await ToolRegistry.shared.execute(name: toolName, arguments: args)) ?? "工具执行失败"
                    apiMessages.append(["role": "tool", "tool_call_id": toolCallId, "content": result])
                }
                continue // 工具执行完后，让 AI 再跑一轮
            }
            
            if !fullContent.isEmpty {
                messages.append(ChatMessage(role: "assistant", content: fullContent))
                return messages
            }
            
            messages.append(ChatMessage(role: "assistant", content: "（本次回复未生成有效内容）"))
            return messages
        }
        messages.append(ChatMessage(role: "assistant", content: "⚠️ 任务超过最大循环次数。"))
        return messages
    }
    
    private var systemPrompt: String {
        """
        你是 PocketCode，运行在 iOS 上的编程 AI Agent。
        你可以使用工具读写文件、执行命令。
        当用户要求写代码时，直接输出代码块或调用 write_file 工具。
        """
    }
}
