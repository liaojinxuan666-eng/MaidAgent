import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case noAPIKey
    case httpError(Int, String)
    case parseError(String)
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "API URL 格式错误"
        case .noAPIKey: return "未配置 API Key，请前往设置"
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        case .parseError(let msg): return "响应解析失败: \(msg)"
        case .networkError(let msg): return "网络错误: \(msg)"
        }
    }
}

final class APIClient {
    static let shared = APIClient()
    
    private init() {}
    
    /// 读取用户在设置里填的配置
    private func readConfig() throws -> (apiKey: String, baseURL: String, model: String) {
        let apiKey = UserDefaults.standard.string(forKey: "apiKey") ?? ""
        let baseURL = UserDefaults.standard.string(forKey: "baseURL") ?? "https://api.deepseek.com"
        let model = UserDefaults.standard.string(forKey: "modelName") ?? "deepseek-chat"
        
        guard !apiKey.isEmpty else {
            throw APIError.noAPIKey
        }
        return (apiKey, baseURL, model)
    }
    
    /// 核心方法：发送对话请求
    /// - Parameters:
    ///   - messages: 完整的对话历史（OpenAI 格式）
    ///   - tools: 可选的工具定义（OpenAI function calling 格式）
    /// - Returns: 原始 JSON 响应
    func chat(
        messages: [[String: Any]],
        tools: [[String: Any]]? = nil
    ) async throws -> [String: Any] {
        
        let config = try readConfig()
        
        // 拼接完整 URL
        let base = config.baseURL.hasSuffix("/") ? String(config.baseURL.dropLast()) : config.baseURL
        guard let url = URL(string: "\(base)/chat/completions") else {
            throw APIError.invalidURL
        }
        
        // 构建请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 1800
        
        var body: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "stream": false
        ]
        
        if let tools = tools, !tools.isEmpty {
            body["tools"] = tools
            body["tool_choice"] = "auto"
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // 发送请求
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }
        
        // 检查 HTTP 状态码
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "未知错误"
            throw APIError.httpError(httpResponse.statusCode, msg)
        }
        
        // 解析 JSON
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.parseError("返回不是合法的 JSON")
        }
        
        return json
    }
}