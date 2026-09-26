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
    
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    if messages.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "terminal")
                                .font(.system(size: 60))
                                .foregroundColor(.blue.opacity(0.8))
                                .padding(.top, 120)
                            Text("今天要在 \(projectContext ?? "沙箱") 里写点什么？")
                                .font(.title3)
                            Text("或者让我帮你重构、修 Bug、看 GitHub 源码")
                                .font(.caption).foregroundColor(.gray)
                        }
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
                // ✨ 修复键盘：下拉可收起
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture {
                    // ✨ 物理级强制收起键盘
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            
            // 底部输入区
            VStack(spacing: 0) {
                Divider().background(Color.gray.opacity(0.2))
                HStack(alignment: .bottom, spacing: 12) {
                    Button(action: { showAttachmentSheet = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary.opacity(0.8))
                            .frame(width: 38, height: 38)
                            .background(Color(UIColor.tertiarySystemFill))
                            .clipShape(Circle())
                    }
                    .padding(.bottom, 2)
                    
                    HStack(alignment: .bottom, spacing: 8) {
                        TextField("输入指令...", text: $inputText, axis: .vertical)
                            .lineLimit(1...6)
                            .padding(.vertical, 10)
                            .padding(.leading, 8)
                            .focused($isInputFocused)
                        
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
                                .background(inputText.isEmpty ? Color.gray.opacity(0.4) : Color.blue)
                                .clipShape(Circle())
                        }
                        .disabled(inputText.isEmpty || isLoading)
                        .padding(.trailing, 4).padding(.bottom, 4)
                    }
                    .padding(.horizontal, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.gray.opacity(0.2), lineWidth: 0.5))
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                Text("内容由 AI 生成").font(.system(size: 10)).foregroundColor(.gray).padding(.bottom, 8)
            }
            .background(Color.black)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(projectContext ?? "PocketCode")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { showSidebar.toggle() }) {
                    Image(systemName: "line.3.horizontal").font(.system(size: 18, weight: .medium))
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
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color(UIColor.tertiarySystemFill))
                    .clipShape(Capsule())
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    if let pid = projectId { _ = store.createSession(projectId: pid, title: "新会话") }
                    else { messages.removeAll() }
                }) {
                    Image(systemName: "square.and.pencil").font(.system(size: 18))
                }
            }
        }
        .sheet(isPresented: $showSidebar) {
            NavigationView {
                List {
                    Text("历史会话").foregroundColor(.gray)
                }
                .navigationTitle("会话历史")
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { showSidebar = false } } }
            }.preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showAttachmentSheet) {
            AttachmentSheet(isPresented: $showAttachmentSheet, onSelectLocalFile: { showFileImporter = true }, onSelectGitHub: { inputText += " [GitHub 链接] " }, onSelectWeb: { inputText += " [网页链接] " })
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.plainText, .sourceCode, .data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    let content = try String(contentsOf: url, encoding: .utf8)
                    // ✨ 修复：把文件真正写入沙箱 VFS
                    let filename = url.lastPathComponent
                    let vfsPath = "uploads/\(filename)"
                    try VirtualFileSystem.shared.writeFile(vfsPath, content: content)
                    
                    // 在输入框提示，AI 可以读到这个文件
                    inputText += "【我上传了文件：\(vfsPath)，请读取】"
                } catch {
                    fileImportError = "读取文件失败: \(error.localizedDescription)"
                }
            case .failure(let error):
                fileImportError = "选择文件失败: \(error.localizedDescription)"
            }
        }
        .alert("文件导入错误", isPresented: .constant(fileImportError != nil), actions: {
            Button("好") { fileImportError = nil }
        }, message: { Text(fileImportError ?? "") })
        .onAppear { loadMessagesFromStore() }
    }
    
    private func loadMessagesFromStore() {
        guard let pid = projectId, let sid = sessionId, let session = store.getSession(projectId: pid, sessionId: sid) else { return }
        messages = session.messages
    }
    
    private func saveMessagesToStore() {
        guard let pid = projectId, let sid = sessionId else { return }
        store.updateSessionMessages(projectId: pid, sessionId: sid, messages: messages)
    }
    
    func sendMessage(_ text: String) async {
        guard !text.isEmpty else { return }
        await MainActor.run {
            messages.append(ChatMessage(role: "user", content: text))
            isLoading = true
            saveMessagesToStore()
        }
        do {
            let updatedMessages = try await AgentLoop.shared.run(initialMessages: messages)
            await MainActor.run {
                self.messages = updatedMessages
                isLoading = false
                saveMessagesToStore()
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

// ✨ 全新漂亮的消息气泡组件
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
                // 仿 Claude Code / Kimi 的工具调用卡片
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