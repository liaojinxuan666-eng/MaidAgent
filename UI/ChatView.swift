import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    var projectId: UUID? = nil
    var sessionId: UUID? = nil
    var projectContext: String? = nil

    @StateObject private var store = ProjectStore.shared
    
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isLoading = false
    @State private var showSidebar = false
    @State private var showAttachmentSheet = false
    @State private var showFileImporter = false
    @State private var fileImportError: String? = nil
    
    // ✨ 流式渲染专用的临时消息，避免频繁重绘整个 messages 数组
    @State private var streamingMessage: ChatMessage? = nil
    
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - 消息列表 / 空状态
            ScrollViewReader { proxy in
                ScrollView {
                    if messages.isEmpty && streamingMessage == nil {
                        VStack(spacing: 16) {
                            Image(systemName: "terminal")
                                .font(.system(size: 60))
                                .foregroundColor(.blue.opacity(0.8))
                                .padding(.top, 120)
                            
                            Text("今天要在 \(projectContext ?? "沙箱") 里写点什么？")
                                .font(.title3)
                                .foregroundColor(.primary)
                            
                            Text("或者让我帮你重构、修 Bug、看 GitHub 源码")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 40)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            // 历史消息
                            ForEach(messages) { msg in
                                MessageBubble(message: msg).id(msg.id)
                            }
                            
                            // 流式消息（独立渲染）
                            if let streamMsg = streamingMessage {
                                MessageBubble(message: streamMsg).id(streamMsg.id)
                            } else if isLoading {
                                HStack(spacing: 8) {
                                    ProgressView().scaleEffect(0.8)
                                    Text("思考中...")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Spacer()
                                }
                                .padding(.horizontal)
                                .id("loading_indicator")
                            }
                        }
                        .padding()
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                // 流式内容更新时自动滚动
                .onChange(of: streamingMessage?.content) { _ in
                    if let streamId = streamingMessage?.id {
                        DispatchQueue.main.async {
                            withAnimation { proxy.scrollTo(streamId, anchor: .bottom) }
                        }
                    }
                }
            }
            
            // MARK: - 底部输入区
            VStack(spacing: 0) {
                Divider().background(Color.gray.opacity(0.2))
                
                HStack(alignment: .bottom, spacing: 12) {
                    // + 号附件按钮
                    Button(action: { showAttachmentSheet = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary.opacity(0.8))
                            .frame(width: 38, height: 38)
                            .background(Color(UIColor.tertiarySystemFill))
                            .clipShape(Circle())
                    }
                    .padding(.bottom, 2)
                    
                    // 胶囊输入框
                    HStack(alignment: .bottom, spacing: 8) {
                        TextField("输入指令...", text: $inputText, axis: .vertical)
                            .lineLimit(1...6)
                            .padding(.vertical, 10)
                            .padding(.leading, 8)
                            .foregroundColor(.primary)
                            .focused($isInputFocused)
                        
                        // 发送按钮
                        Button(action: {
                            let text = inputText
                            inputText = ""
                            isInputFocused = false
                            Task { await sendMessage(text) }
                        }) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                                .background(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.4) : Color.blue)
                                .clipShape(Circle())
                        }
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                        .padding(.trailing, 4)
                        .padding(.bottom, 4)
                    }
                    .padding(.horizontal, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.gray.opacity(0.2), lineWidth: 0.5))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                
                Text("内容由 AI 生成")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .padding(.bottom, 8)
            }
            .background(Color.black)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(projectContext ?? "PocketCode")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { showSidebar.toggle() }) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.primary)
                }
            }
            
            ToolbarItem(placement: .principal) {
                Menu {
                    Button("DeepSeek Chat") {}
                    Button("GLM-4") {}
                } label: {
                    HStack(spacing: 4) {
                        Text("PocketCode AI").font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(UIColor.tertiarySystemFill))
                    .clipShape(Capsule())
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    if let pid = projectId {
                        _ = store.createSession(projectId: pid, title: "新会话")
                    } else {
                        messages.removeAll()
                    }
                }) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18))
                }
            }
        }
        .sheet(isPresented: $showSidebar) {
            NavigationView {
                List {
                    if let pid = projectId, let project = store.getProject(pid) {
                        ForEach(project.sessions) { session in
                            NavigationLink(destination: ChatView(projectId: pid, sessionId: session.id, projectContext: project.name)) {
                                Text(session.title)
                            }
                        }
                    } else {
                        Text("暂无历史会话").foregroundColor(.gray)
                    }
                }
                .navigationTitle("会话历史")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("完成") { showSidebar = false }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showAttachmentSheet) {
            AttachmentSheet(
                isPresented: $showAttachmentSheet,
                onSelectLocalFile: { showFileImporter = true },
                onSelectGitHub: { inputText += " [GitHub 链接] " },
                onSelectWeb: { inputText += " [网页链接] " }
            )
        }
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
                    let filename = url.lastPathComponent
                    let vfsPath = "uploads/\(filename)"
                    try VirtualFileSystem.shared.writeFile(vfsPath, content: content)
                    inputText += "【我上传了文件：\(vfsPath)，请读取并分析】"
                } catch {
                    fileImportError = "读取文件失败: \(error.localizedDescription)"
                }
            case .failure(let error):
                fileImportError = "选择文件失败: \(error.localizedDescription)"
            }
        }
        .alert("文件导入错误", isPresented: .constant(fileImportError != nil), actions: {
            Button("好") { fileImportError = nil }
        }, message: {
            Text(fileImportError ?? "")
        })
        .onAppear { loadMessagesFromStore() }
    }
    
    // MARK: - 持久化逻辑
    private func loadMessagesFromStore() {
        guard let pid = projectId, let sid = sessionId,
              let session = store.getSession(projectId: pid, sessionId: sid) else { return }
        messages = session.messages
    }
    
    private func saveMessagesToStore() {
        guard let pid = projectId, let sid = sessionId else { return }
        store.updateSessionMessages(projectId: pid, sessionId: sid, messages: messages)
    }
    
    // MARK: - 发送消息（带节流的流式打字机 + 断网保护）
    @MainActor
    func sendMessage(_ text: String) async {
        guard !text.isEmpty else { return }
        
        messages.append(ChatMessage(role: "user", content: text))
        isLoading = true
        saveMessagesToStore()
        
        let streamingId = UUID()
        self.streamingMessage = ChatMessage(id: streamingId, role: "assistant", content: "")
        
        var buffer = ""
        var lastUpdate = Date()
        
        do {
            let finalMessages = try await AgentLoop.shared.run(initialMessages: messages) { token in
                buffer += token
                // 节流：每 300ms 更新一次 UI，避免把手机卡死
                if Date().timeIntervalSince(lastUpdate) > 0.3 {
                    let currentText = buffer
                    lastUpdate = Date()
                    Task { @MainActor in
                        if self.streamingMessage?.id == streamingId {
                            self.streamingMessage?.content = currentText
                        }
                    }
                }
            }
            
            self.messages = finalMessages
            self.streamingMessage = nil
            self.isLoading = false
            saveMessagesToStore()
            
        } catch {
            // 断网保护：把已经收到的部分内容保存下来
            if !buffer.isEmpty {
                self.messages.append(ChatMessage(role: "assistant", content: buffer + "\n\n[网络中断，已保存部分内容]"))
            }
            self.messages.append(ChatMessage(role: "assistant", content: "网络错误: \(error.localizedDescription)。请检查代理或稍后重试。"))
            self.streamingMessage = nil
            self.isLoading = false
            saveMessagesToStore()
        }
    }
}

// MARK: - 消息气泡
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
            } else if message.type == "tool_call" {
                // Claude Code 风格的工具调用卡片
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                        Text("调用工具: \(message.toolName ?? "未知")")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.blue)
                    }
                    if let args = message.toolArgs, !args.isEmpty {
                        Text(args)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.gray)
                            .lineLimit(3)
                            .padding(6)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(6)
                    }
                }
                .padding(10)
                .background(Color(UIColor.tertiarySystemFill))
                .cornerRadius(12)
                Spacer()
            } else {
                Text(message.content.isEmpty ? " " : message.content)
                    .padding(12)
                    .background(Color(UIColor.secondarySystemFill))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                Spacer()
            }
        }
    }
}
