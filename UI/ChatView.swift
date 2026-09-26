import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    // 项目与会话 ID（如果是从项目里进来的，这两个参数会传入）
    var projectId: UUID? = nil
    var sessionId: UUID? = nil
    var projectContext: String? = nil  // 保留，用于顶部显示项目名

    @StateObject private var store = ProjectStore.shared
    
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isLoading = false
    @State private var showSidebar = false
    
    // 附件与 Sheet 状态
    @State private var showAttachmentSheet = false
    @State private var showFileImporter = false
    @State private var fileImportError: String? = nil
    
    // ⌨️ 键盘焦点控制（修复键盘收不下去的 Bug）
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - 消息列表 / 空状态
            ScrollViewReader { proxy in
                ScrollView {
                    if messages.isEmpty {
                        VStack(spacing: 16) {
                            // 仿 Kimi 空状态
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
                            ForEach(messages) { msg in
                                MessageBubble(message: msg).id(msg.id)
                            }
                            if isLoading {
                                HStack {
                                    ProgressView()
                                    Text("思考中...").font(.caption).foregroundColor(.gray)
                                    Spacer()
                                }.padding(.horizontal)
                            }
                        }
                        .padding()
                    }
                }
                // 下拉收起键盘
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            
            // MARK: - 底部输入区（仿 Kimi）
            VStack(spacing: 0) {
                Divider().background(Color.gray.opacity(0.2))
                
                HStack(alignment: .bottom, spacing: 12) {
                    // + 号按钮，弹出底边抽屉
                    Button(action: { showAttachmentSheet = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary.opacity(0.8))
                            .frame(width: 38, height: 38)
                            .background(Color(UIColor.tertiarySystemFill))
                            .clipShape(Circle())
                    }
                    .padding(.bottom, 2)
                    
                    // 胶囊输入框 + 毛玻璃
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
                            isInputFocused = false // 发送后收起键盘
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
                
                // 底部小字（仿 Kimi）
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
            // 顶部导航栏
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { showSidebar.toggle() }) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.primary)
                }
            }
            ToolbarItem(placement: .principal) {
                // 模型选择器（胶囊状）
                Menu {
                    Button("DeepSeek Chat") {}
                    Button("GLM-4") {}
                    Button("Qwen-Coder") {}
                } label: {
                    HStack(spacing: 4) {
                        Text("PocketCode AI")
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(UIColor.tertiarySystemFill))
                    .clipShape(Capsule())
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    // 如果在项目里，新建会话
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
            // 侧边栏（历史会话）
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
                onSelectGitHub: { inputText += " [GitHub 仓库链接] " },
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
                    inputText += "\n```\n\(content)\n```\n"
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
        .onAppear {
            loadMessagesFromStore()
        }
    }
    
    // MARK: - 数据持久化逻辑
    private func loadMessagesFromStore() {
        guard let pid = projectId, let sid = sessionId,
              let session = store.getSession(projectId: pid, sessionId: sid) else { return }
        messages = session.messages
    }
    
    private func saveMessagesToStore() {
        guard let pid = projectId, let sid = sessionId else { return }
        store.updateSessionMessages(projectId: pid, sessionId: sid, messages: messages)
    }
    
    // MARK: - 发送消息（调用真正的 AgentLoop）
    func sendMessage(_ text: String) async {
        guard !text.isEmpty else { return }
        
        await MainActor.run {
            messages.append(ChatMessage(role: "user", content: text))
            isLoading = true
            saveMessagesToStore() // 立刻保存用户消息
        }
        
        do {
            // 调用 Agent 循环
            let updatedMessages = try await AgentLoop.shared.run(initialMessages: messages)
            await MainActor.run {
                self.messages = updatedMessages
                isLoading = false
                saveMessagesToStore() // AI 回复后保存
            }
        } catch {
            await MainActor.run {
                messages.append(ChatMessage(role: "assistant", content: "错误: \(error.localizedDescription)"))
                isLoading = false
                saveMessagesToStore()
            }
        }
    }
}

// MARK: - 消息气泡组件
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