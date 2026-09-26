import SwiftUI

struct ChatView: View {
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isLoading = false
    @State private var showSidebar = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 消息列表
                ScrollViewReader { proxy in
                    ScrollView {
                        if messages.isEmpty {
                            Text("无会话记录，点击左上角 + 新建")
                                .foregroundColor(.gray)
                                .padding(.top, 100)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                ForEach(messages) { msg in
                                    MessageBubble(message: msg)
                                        .id(msg.id)
                                }
                                if isLoading {
                                    HStack {
                                        ProgressView()
                                        Text("思考中...").font(.caption).foregroundColor(.gray)
                                        Spacer()
                                    }
                                    .padding(.horizontal)
                                }
                            }
                            .padding()
                        }
                    }
                    .onChange(of: messages.count) { _ in
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
                
                // 底部输入区（多行、带加号附件）
                VStack(spacing: 0) {
                    Divider().background(Color.gray.opacity(0.3))
                    HStack(alignment: .bottom, spacing: 12) {
                        // 附件按钮
                        Button(action: {
                            // TODO: 后续实现 UIDocumentPicker 上传文件
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.gray)
                        }
                        .padding(.bottom, 6)
                        
                        // 多行输入框
                        TextField("输入指令...", text: $inputText, axis: .vertical)
                            .lineLimit(1...6)
                            .padding(10)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(18)
                            .foregroundColor(.white)
                        
                        // 发送按钮
                        Button(action: {
                            let text = inputText
                            inputText = ""
                            Task { await sendMessage(text) }
                        }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                                .foregroundColor(inputText.isEmpty ? .gray : .white)
                        }
                        .disabled(inputText.isEmpty || isLoading)
                        .padding(.bottom, 6)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color.black)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("PocketCode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 左上角：历史会话（侧边栏）
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showSidebar.toggle() }) {
                        Image(systemName: "sidebar.left")
                            .foregroundColor(.white)
                    }
                }
                // 右上角：新建会话
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        messages.removeAll()
                    }) {
                        Image(systemName: "square.and.pencil")
                            .foregroundColor(.white)
                    }
                }
            }
            .sheet(isPresented: $showSidebar) {
                // 侧边栏历史会话列表
                NavigationView {
                    List {
                        Text("历史会话列表（后续接入本地持久化）")
                            .foregroundColor(.gray)
                    }
                    .navigationTitle("会话历史")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("完成") { showSidebar = false }
                        }
                    }
                }
                .preferredColorScheme(.dark)
            }
        }
    }
    
    // MARK: - 真正的 API 请求（告别“你好”）
    func sendMessage(_ text: String) async {
        guard !text.isEmpty else { return }
        await MainActor.run {
            messages.append(ChatMessage(role: "user", content: text))
            isLoading = true
        }
        
        // 读取设置里的 API 配置
        let apiKey = UserDefaults.standard.string(forKey: "apiKey") ?? ""
        let baseURL = UserDefaults.standard.string(forKey: "baseURL") ?? "https://api.deepseek.com"
        let modelName = UserDefaults.standard.string(forKey: "modelName") ?? "deepseek-chat"
        
        // 组装真实的请求
        guard let url = URL(string: "\(baseURL)/chat/completions") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 构建消息历史
        let apiMessages = messages.map { ["role": $0.role, "content": $0.content] }
        let body: [String: Any] = [
            "model": modelName,
            "messages": apiMessages
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                await MainActor.run {
                    messages.append(ChatMessage(role: "assistant", content: content))
                    isLoading = false
                }
            } else {
                await MainActor.run {
                    messages.append(ChatMessage(role: "assistant", content: "API 返回格式错误，请检查设置中的 BaseURL 和模型名。"))
                    isLoading = false
                }
            }
        } catch {
            await MainActor.run {
                messages.append(ChatMessage(role: "assistant", content: "网络请求失败: \(error.localizedDescription)"))
                isLoading = false
            }
        }
    }
}

// 消息气泡组件
struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == "user" {
                Spacer()
                Text(message.content)
                    .padding(12)
                    .background(Color.blue.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(16)
            } else {
                Text(message.content)
                    .padding(12)
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.white)
                    .cornerRadius(16)
                Spacer()
            }
        }
    }
}