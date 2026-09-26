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

enum StreamEvent {
    case text(String)
    case toolCalls([[String: Any]])
    case done
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
    
    func chatStream(messages: [[String: Any]], tools: [[String: Any]]? = nil) -> AsyncThrowingStream<StreamEvent, Error> {
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
                    request.timeoutInterval = 1800
                    
                    var body: [String: Any] = ["model": config.model, "messages": messages, "stream": true]
                    if let tools = tools, !tools.isEmpty {
                        body["tools"] = tools
                        body["tool_choice"] = "auto"
                    }
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    
                    // 配置 URLSession 保持长连接
                    let sessionConfig = URLSessionConfiguration.default
                    sessionConfig.timeoutIntervalForRequest = 1800
                    sessionConfig.timeoutIntervalForResource = 1800
                    sessionConfig.waitsForConnectivity = true
                    let session = URLSession(configuration: sessionConfig)
                    
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                        throw APIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0, "服务端拒绝请求")
                    }
                    
                    var toolCallsDict: [Int: [String: Any]] = [:]
                    
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))
                            if jsonString == "[DONE]" { break }
                            
                            if let data = jsonString.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let choices = json["choices"] as? [[String: Any]],
                               let delta = choices.first?["delta"] as? [String: Any] {
                                
                                // 1. 收到文字
                                if let content = delta["content"] as? String, !content.isEmpty {
                                    continuation.yield(.text(content))
                                }
                                
                                // 2. 收到工具调用（流式模式下，工具参数是分片传过来的）
                                if let deltaToolCalls = delta["tool_calls"] as? [[String: Any]] {
                                    for tc in deltaToolCalls {
                                        guard let index = tc["index"] as? Int else { continue }
                                        if toolCallsDict[index] == nil {
                                            toolCallsDict[index] = ["id": "", "type": "function", "function": ["name": "", "arguments": ""]]
                                        }
                                        if let id = tc["id"] as? String { toolCallsDict[index]?["id"] = id }
                                        if let function = tc["function"] as? [String: Any] {
                                            var f = toolCallsDict[index]?["function"] as? [String: Any] ?? [:]
                                            if let name = function["name"] as? String { f["name"] = name }
                                            if let args = function["arguments"] as? String {
                                                f["arguments"] = (f["arguments"] as? String ?? "") + args
                                            }
                                            toolCallsDict[index]?["function"] = f
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    let finalCalls = toolCallsDict.sorted { $0.key < $1.key }.map { $0.value }
                    if !finalCalls.isEmpty {
                        continuation.yield(.toolCalls(finalCalls))
                    }
                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
