import Foundation

final class AgentLoop {
    static let shared = AgentLoop()
    
    private init() {}
    private let maxIterations = 15
    
    @MainActor
    func run(initialMessages: [ChatMessage]) async throws -> [ChatMessage] {
        var messages = initialMessages
        
        var apiMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]
        apiMessages.append(contentsOf: messages.map { ["role": $0.role, "content": $0.content] })
        
        var iteration = 0
        
        while iteration < maxIterations {
            iteration += 1
            
            let toolsSchema = ToolRegistry.shared.apiSchema()
            let response = try await APIClient.shared.chat(messages: apiMessages, tools: toolsSchema)
            
            guard let choices = response["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any] else {
                throw APIError.parseError("无法解析 choices 结构")
            }
            
            if let toolCalls = message["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
                apiMessages.append(message)
                
                for toolCall in toolCalls {
                    guard let function = toolCall["function"] as? [String: Any],
                          let toolName = function["name"] as? String,
                          let argsString = function["arguments"] as? String,
                          let toolCallId = toolCall["id"] as? String else { continue }
                    
                    let argsData = argsString.data(using: .utf8) ?? Data()
                    let args = (try? JSONSerialization.jsonObject(with: argsData) as? [String: Any]) ?? [:]
                    
                    // ✨ UI 优化：以特殊类型插入工具调用消息，而不是纯文本
                    messages.append(ChatMessage(role: "assistant", content: "", type: "tool_call", toolName: toolName, toolArgs: argsString))
                    
                    let result = (try? await ToolRegistry.shared.execute(name: toolName, arguments: args)) ?? "工具执行失败"
                    
                    apiMessages.append([
                        "role": "tool",
                        "tool_call_id": toolCallId,
                        "content": result
                    ])
                }
                continue
            }
            
            if let content = message["content"] as? String, !content.isEmpty {
                messages.append(ChatMessage(role: "assistant", content: content, type: "text"))
                return messages
            }
        }
        
        messages.append(ChatMessage(role: "assistant", content: "⚠️ 任务超过了最大循环次数，已自动停止。", type: "text"))
        return messages
    }
    
    private var systemPrompt: String {
        """
        你是 PocketCode，一个运行在 iOS 上的编程 AI Agent。
        你的工作区是一个虚拟文件系统（沙箱），根目录是 /。
        你可以使用工具读取、写入、列出文件和执行命令。
        所有路径都相对于根目录，不要尝试使用真实 iOS 路径。
        """
    }
}