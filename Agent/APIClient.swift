import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL, noAPIKey, httpError(Int, String), parseError(String), networkError(String)
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "API URL 格式错误"
        case .noAPIKey: return "未配置 API Key"
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        case .parseError(let msg): return "解析失败: \(msg)"
        case .networkError(let msg): return "网络错误: \(msg)"
        }
    }
}

final class APIClient {
    static let shared = APIClient()
    private init() {}
    
    private func readConfig() throws -> (apiKey: String, baseURL: String, model: String) {
        let apiKey = UserDefaults.standard.string(forKey: "apiKey") ?? ""
        let baseURL = UserDefaults.standard.string(forKey: "baseURL") ?? "https://api.deepseek.com"
        let model = UserDefaults.standard.string(forKey: "modelName") ?? "deepseek-chat"
        guard !apiKey.isEmpty else { throw APIError.noAPIKey }
        return (apiKey, baseURL, model)
    }
    
    /// 流式对话请求
    func chatStream(messages: [[String: Any]], tools: [[String: Any]]? = nil) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let config = try readConfig()
                    let base = config.baseURL.hasSuffix("/") ? String(config.baseURL.dropLast()) : config.baseURL
                    guard let url = URL(string: "\(base)/chat/completions") else { throw APIError.invalidURL }
                    
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.addValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
                    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = 1800 // 30分钟总超时
                    
                    var body: [String: Any] = [
                        "model": config.model,
                        "messages": messages,
                        "stream": true // 👈 开启流式
                    ]
                    if let tools = tools, !tools.isEmpty {
                        body["tools"] = tools
                        body["tool_choice"] = "auto"
                    }
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    
                    // 使用 bytes(for:) 实现流式读取
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                        throw APIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0, "服务端拒绝请求")
                    }
                    
                    for try await line in bytes.lines {
                        // SSE 格式：data: {...}
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))
                            if jsonString == "[DONE]" { break }
                            
                            if let data = jsonString.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let choices = json["choices"] as? [[String: Any]],
                               let delta = choices.first?["delta"] as? [String: Any] {
                                
                                // 提取正文内容
                                if let content = delta["content"] as? String {
                                    continuation.yield(content)
                                }
                                
                                // 提取工具调用（暂时只传回提示，防止卡死）
                                if let toolCalls = delta["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
                                    // 工具调用的流式解析比较复杂，第一版我们只处理文本
                                }
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}