import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isLoading = false
    @State private var showSidebar = false
    
    // 文件上传状态
    @State private var showFileImporter = false
    @State private var fileImportError: String? = nil

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 消息列表
                ScrollViewReader { proxy in
                    ScrollView {
                        if messages.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "message")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                                Text("暂无会话记录")
                                    .foregroundColor(.gray)
                            }
                            .padding(.top, 120)
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
                
                // 现代化底部输入区
                VStack(spacing: 0) {
                    Divider().background(Color.gray.opacity(0.2))
                    
                    HStack(alignment: .bottom, spacing: 10) {
                        // + 号附件按钮（圆形灰底）
                        Button(action: { showFileImporter = true }) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.primary.opacity(0.7))
                                .frame(width: 34, height: 34)
                                .background(Color(UIColor.tertiarySystemFill))
                                .clipShape(Circle())
                        }
                        .padding(.bottom, 2)
                        
                        // 输入框（胶囊 + 毛玻璃）
                        HStack(alignment: .bottom, spacing: 6) {
                            TextField("输入指令...", text: $inputText, axis: .vertical)
                                .lineLimit(1...6)
                                .padding(.vertical, 8)
                                .padding(.leading, 6)
                                .foregroundColor(.primary)
                            
                            // 发送按钮（胶囊内嵌圆圈）
                            Button(action: {
                                let text = inputText
                                inputText = ""
                                Task { await sendMessage(text) }
                            }) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 28, height: 28)
                                    .background(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.4) : Color.blue)
                                    .clipShape(Circle())
                            }
                            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                            .padding(.trailing, 4)
                            .padding(.bottom, 3)
                        }
                        .padding(.horizontal, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                        )
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .background(Color.black)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("PocketCode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showSidebar.toggle() }) {
                        Image(systemName: "sidebar.left").foregroundColor(.primary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { messages.removeAll() }) {
                        Image(systemName: "square.and.pencil").foregroundColor(.primary)
                    }
                }
            }
            // 历史会话侧边栏
            .sheet(isPresented: $showSidebar) {
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
            // 文件选择器
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.plainText, .sourceCode, .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        let content = try String(contentsOf: url, encoding: .utf8)
                        // 把文件内容拼接到输入框，方便你直接发送给 AI 分析
                        inputText += "\n```\n\(content)\n```\n"
                    } catch {
                        fileImportError = "读取文件失败: \(error.localizedDescription)"
                    }
                case .failure(let error):
                    fileImportError = "选择文件失败: \(error.localizedDescription)"
                }
            }
            // 文件导入错误提示
            .alert("文件导入错误", isPresented: .constant(fileImportError != nil), actions: {
                Button("好") { fileImportError = nil }
            }, message: {
                Text(fileImportError ?? "")
            })
        }
    }
    
    // MARK: - 真正的 API 请求（告别“你好”）
    func sendMessage(_ text: String) async {
        guard !text.isEmpty else { return }
        await MainActor.run {
            messages.append(ChatMessage(role: "user", content: text))
            isLoading = true
        }
        
        let apiKey = UserDefaults.standard.string(forKey: "apiKey") ?? ""
        let baseURL = UserDefaults.standard.string(forKey: "baseURL") ?? "https://api.deepseek.com"
        let modelName = UserDefaults.standard.string(forKey: "modelName") ?? "deepseek-chat"
        
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            await MainActor.run {
                messages.append(ChatMessage(role: "assistant", content: "URL 格式错误，请检查设置里的 Base URL。"))
                isLoading = false
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
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
                    messages.append(ChatMessage(role: "assistant", content: "API 返回格式错误，请检查设置。"))
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
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                Text(message.content)
                    .padding(12)
                    .background(Color(UIColor.secondarySystemFill))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                Spacer()
            }
        }
    }
}