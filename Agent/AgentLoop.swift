import Foundation

final class AgentLoop {
    static let shared = AgentLoop()
    
    private init() {}
    
    // 防止 AI 死循环，最多跑 15 轮工具调用
    private let maxIterations = 15
    
    /// 核心方法：运行一次 Agent 对话
    /// - Parameter messages: 当前的聊天记录
    /// - Returns: 更新后的聊天记录（包含 AI 的最终回复）
    @MainActor
    func run(initialMessages: [ChatMessage]) async throws -> [ChatMessage] {
        var messages = initialMessages
        
        // 1. 把聊天记录转成 API 格式，并注入系统提示词
        var apiMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]
        apiMessages.append(contentsOf: messages.map { ["role": $0.role, "content": $0.content] })
        
        var iteration = 0
        
        while iteration < maxIterations {
            iteration += 1
            
            // 2. 发起 API 请求（带上工具定义）
            let toolsSchema = ToolRegistry.shared.apiSchema()
            let response = try await APIClient.shared.chat(
                messages: apiMessages,
                tools: toolsSchema
            )
            
            // 3. 解析响应
            guard let choices = response["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any] else {
                throw APIError.parseError("无法解析 choices 结构")
            }
            
            // 4. 检查 AI 是否要调用工具
            if let toolCalls = message["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
                // 把 AI 这一轮的 message（含 tool_calls）加入到历史中
                apiMessages.append(message)
                
                // 依次执行每个工具
                for toolCall in toolCalls {
                    guard let function = toolCall["function"] as? [String: Any],
                          let toolName = function["name"] as? String,
                          let argsString = function["arguments"] as? String,
                          let toolCallId = toolCall["id"] as? String else {
                        continue
                    }
                    
                    let argsData = argsString.data(using: .utf8) ?? Data()
                    let args = (try? JSONSerialization.jsonObject(with: argsData) as? [String: Any]) ?? [:]
                    
                    // 在 UI 上显示“正在调用工具”
                    messages.append(ChatMessage(role: "assistant", content: "🔧 正在调用工具: \(toolName)..."))
                    
                    // 执行工具
                    let result = (try? await ToolRegistry.shared.execute(name: toolName, arguments: args)) ?? "工具执行失败"
                    
                    // 把工具执行结果喂回给 AI
                    apiMessages.append([
                        "role": "tool",
                        "tool_call_id": toolCallId,
                        "content": result
                    ])
                }
                
                // 继续循环，让 AI 根据工具结果决定下一步
                continue
            }
            
            // 5. 如果 AI 没有调用工具，就是最终回复
            if let content = message["content"] as? String, !content.isEmpty {
                messages.append(ChatMessage(role: "assistant", content: content))
                return messages
            }
        }
        
        // 超出最大迭代次数
        messages.append(ChatMessage(role: "assistant", content: "⚠️ 任务超过了最大循环次数（\(maxIterations) 轮），已自动停止。"))
        return messages
    }
    
    // 系统提示词：告诉 AI 它是什么、它能用什么工具、行为规范
    private var systemPrompt: String {
        """
        你是 PocketCode，一个运行在 iOS 上的编程 AI Agent。
        你的工作区是一个虚拟文件系统（沙箱），根目录是 /。
        
        你可以使用以下工具：
        - list_dir: 列出目录下的文件和文件夹
        - read_file: 读取文件内容
        - write_file: 写入或覆盖文件内容
        - execute_command: 在沙箱终端执行命令（支持 ls, cat, mkdir, rm, grep 等）
        
        行为规范：
        1. 所有路径都是相对于虚拟文件系统根目录 / 的，不要尝试使用真实 iOS 路径。
        2. 修改代码前，先用 list_dir 和 read_file 了解项目结构。
        3. 不要执行 su、sudo 等越权命令，沙箱会直接拒绝。
        4. 保持回复精炼专业，不要输出无关的寒暄。
        5. 如果任务完成，直接给出总结，不要继续调用工具。
        """
    }
}