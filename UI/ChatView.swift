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
    
    @State private var streamingMessage: ChatMessage? = nil
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    if messages.isEmpty && streamingMessage == nil {
                        VStack(spacing: 16) {
                            Image(systemName: "terminal")
                                .font(.system(size: 60))
                                .foregroundColor(.blue.opacity(0.8))
                                .padding(.top, 120)
                            Text("今天要在 \(projectContext ?? "沙箱") 里写点什么？")
                                .font(.title3).foregroundColor(.primary)
                            Text("或者让我帮你重构、修 Bug、看 GitHub 源码")
                                .font(.caption).foregroundColor(.gray)
                        }
                        .padding(.top, 40)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            // 消息分组渲染
                            ForEach(groupedMessages) { group in
                                switch group {
                                case .single(let msg):
                                    MessageBubble(message: msg, onRegenerate: {
                                        regenerateLastResponse()
                                    }).id(msg.id)
                                case .thinking(let msgs):
                                    ThinkingBlockView(messages: msgs).id(group.id)
                                }
                            }
                            
                            if let streamMsg = streamingMessage {
                                MessageBubble(message: streamMsg).id(streamMsg.id)
                            } else if isLoading {
                                HStack(spacing: 8) {
                                    ProgressView().scaleEffect(0.8)
                                    Text("思考中...").font(.caption).foregroundColor(.gray)
                                    Spacer()
                                }.padding(.horizontal)
                            }
                        }
                        .padding()
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: streamingMessage?.content) { _ in
                    if let streamId = streamingMessage?.id {
                        DispatchQueue.main.async {
                            withAnimation { proxy.scrollTo(streamId, anchor: .bottom) }
                        }
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
                    }.padding(.bottom, 2)
                    
                    HStack(alignment: .bottom, spacing: 8) {
                        TextField("输入指令...", text: $inputText, axis: .vertical)
                            .lineLimit(1...6)
                            .padding(.vertical, 10).padding(.leading, 8)
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
                                .background(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.4) : Color.blue)
                                .clipShape(Circle())
                        }
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                        .padding(.trailing, 4).padding(.bottom, 4)
                    }
                    .padding(.horizontal, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.gray.opacity(0.2), lineWidth: 0.5))
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                Text("内容由 AI 生成").font(.system(size: 10)).foregroundColor(.gray).padding(.bottom, 8)
            }.background(Color.black)
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
                    if let pid = projectId, let project = store.getProject(pid) {
                        ForEach(project.sessions) { session in
                            NavigationLink(destination: ChatView(projectId: pid, sessionId: session.id, projectContext: project.name)) {
                                Text(session.title)
                            }
                        }
                    } else { Text("暂无历史会话").foregroundColor(.gray) }
                }
                .navigationTitle("会话历史")
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { showSidebar = false } } }
            }.preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showAttachmentSheet) {
            AttachmentSheet(
                isPresented: $showAttachmentSheet,
                onSelectLocalFile: { showFileImporter = true },
                onSelectGitHub: { inputText += " [GitHub 链接] " },
                onSelectWeb: { inputText += " [网页链接] " }
            )
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.plainText, .sourceCode, .data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    let content = try String(contentsOf: url, encoding: .utf8)
                    let vfsPath = "uploads/\(url.lastPathComponent)"
                    try VirtualFileSystem.shared.writeFile(vfsPath, content: content)
                    inputText += "【我上传了文件：\(vfsPath)，请读取并分析】"
                } catch { fileImportError = "读取文件失败: \(error.localizedDescription)" }
            case .failure(let error): fileImportError = "选择文件失败: \(error.localizedDescription)"
            }
        }
        .alert("文件导入错误", isPresented: .constant(fileImportError != nil), actions: {
            Button("好") { fileImportError = nil }
        }, message: { Text(fileImportError ?? "") })
        .onAppear { loadMessagesFromStore() }
    }
    
    // MARK: - 消息分组逻辑
    enum MessageGroup: Identifiable {
        case single(ChatMessage)
        case thinking([ChatMessage])
        
        var id: UUID {
            switch self {
            case .single(let msg): return msg.id
            case .thinking(let msgs): return msgs.first?.id ?? UUID()
            }
        }
    }
    
    var groupedMessages: [MessageGroup] {
        var groups: [MessageGroup] = []
        var currentThinking: [ChatMessage] = []
        
        for msg in messages {
            if msg.type == "thinking" {
                currentThinking.append(msg)
            } else {
                if !currentThinking.isEmpty {
                    groups.append(.thinking(currentThinking))
                    currentThinking = []
                }
                groups.append(.single(msg))
            }
        }
        if !currentThinking.isEmpty {
            groups.append(.thinking(currentThinking))
        }
        return groups
    }
    
    // MARK: - 持久化与发送逻辑
    private func loadMessagesFromStore() {
        guard let pid = projectId, let sid = sessionId, let session = store.getSession(projectId: pid, sessionId: sid) else { return }
        messages = session.messages
    }
    
    private func saveMessagesToStore() {
        guard let pid = projectId, let sid = sessionId else { return }
        store.updateSessionMessages(projectId: pid, sessionId: sid, messages: messages)
    }
    
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
            if !buffer.isEmpty {
                self.messages.append(ChatMessage(role: "assistant", content: buffer + "\n\n[网络中断，已保存部分内容]"))
            }
            self.messages.append(ChatMessage(role: "assistant", content: "网络错误: \(error.localizedDescription)。请检查代理或稍后重试。"))
            self.streamingMessage = nil
            self.isLoading = false
            saveMessagesToStore()
        }
    }
    
    @MainActor
    private func regenerateLastResponse() {
        guard let lastUserMsg = messages.last(where: { $0.role == "user" }) else { return }
        if messages.last?.role == "assistant" { messages.removeLast() }
        if let lastIndex = messages.lastIndex(where: { $0.role == "user" }) { messages.remove(at: lastIndex) }
        Task { await sendMessage(lastUserMsg.content) }
    }
}

// MARK: - DeepSeek 风格的可折叠思考块
struct ThinkingBlockView: View {
    let messages: [ChatMessage]
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile").font(.system(size: 13))
                    Text("已深度思考 (\(messages.count) 步)").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .foregroundColor(.gray)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { msg in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "wrench.and.screwdriver.fill")
                                .font(.system(size: 10)).foregroundColor(.blue).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("调用工具: \(msg.toolName ?? "未知")")
                                    .font(.system(size: 12, weight: .medium)).foregroundColor(.gray)
                                if let args = msg.toolArgs, !args.isEmpty {
                                    Text(args)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.gray.opacity(0.8))
                                        .lineLimit(3)
                                        .padding(6)
                                        .background(Color.black.opacity(0.3))
                                        .cornerRadius(6)
                                }
                            }
                        }
                    }
                }
                .padding(.leading, 12)
                .overlay(Rectangle().frame(width: 1).foregroundColor(.gray.opacity(0.3)), alignment: .leading)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Color(UIColor.tertiarySystemFill))
        .cornerRadius(12)
    }
}

// MARK: - 消息气泡
struct MessageBubble: View {
    let message: ChatMessage
    var onRegenerate: (() -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if message.role == "user" {
                    Spacer()
                    Text(message.content)
                        .padding(12).background(Color.blue).foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .textSelection(.enabled)
                } else {
                    MessageContentView(content: message.content)
                        .padding(12).background(Color(UIColor.secondarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Spacer()
                }
            }
            
            if message.role == "assistant" && message.type == "text" && !message.content.isEmpty {
                HStack(spacing: 24) {
                    Button(action: { UIPasteboard.general.string = message.content }) {
                        HStack(spacing: 4) { Image(systemName: "doc.on.doc"); Text("复制") }
                            .font(.system(size: 12)).foregroundColor(.gray)
                    }
                    if let onRegenerate = onRegenerate {
                        Button(action: onRegenerate) {
                            HStack(spacing: 4) { Image(systemName: "arrow.clockwise"); Text("重试") }
                                .font(.system(size: 12)).foregroundColor(.gray)
                        }
                    }
                    ShareLink(item: message.content) {
                        HStack(spacing: 4) { Image(systemName: "square.and.arrow.up"); Text("分享") }
                            .font(.system(size: 12)).foregroundColor(.gray)
                    }
                    Spacer()
                }.padding(.leading, 12).padding(.top, 4)
            }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.content
            } label: {
                Label("复制全部", systemImage: "doc.on.doc")
            }
            ShareLink(item: message.content) {
                Label("分享", systemImage: "square.and.arrow.up")
            }
        }
    }
}

// MARK: - AI 消息内容渲染器
struct MessageContentView: View {
    let content: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(parseMarkdown(content)) { block in
                if block.type == .code {
                    CodeBlockView(code: block.content, language: block.language ?? "code", isClosed: block.isClosed)
                } else {
                    Text(block.content)
                        .font(.body).foregroundColor(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    
    private func parseMarkdown(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let pattern = "```(\\w*)\\n([\\s\\S]*?)(```|$)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [MarkdownBlock(type: .text, content: text, language: nil, isClosed: true)]
        }
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        var lastIndex = 0
        for match in matches {
            let textRange = NSRange(location: lastIndex, length: match.range.location - lastIndex)
            if textRange.length > 0 {
                let textContent = nsString.substring(with: textRange).trimmingCharacters(in: .whitespacesAndNewlines)
                if !textContent.isEmpty {
                    blocks.append(MarkdownBlock(type: .text, content: textContent, language: nil, isClosed: true))
                }
            }
            let langRange = match.range(at: 1)
            let codeRange = match.range(at: 2)
            let endRange = match.range(at: 3)
            let language = langRange.length > 0 ? nsString.substring(with: langRange) : "code"
            let code = codeRange.length > 0 ? nsString.substring(with: codeRange) : ""
            let isClosed = endRange.length == 3
            blocks.append(MarkdownBlock(type: .code, content: code, language: language, isClosed: isClosed))
            lastIndex = match.range.location + match.range.length
        }
        if lastIndex < nsString.length {
            let remaining = nsString.substring(from: lastIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            if !remaining.isEmpty {
                blocks.append(MarkdownBlock(type: .text, content: remaining, language: nil, isClosed: true))
            }
        }
        return blocks.isEmpty ? [MarkdownBlock(type: .text, content: text, language: nil, isClosed: true)] : blocks
    }
}

struct MarkdownBlock: Identifiable {
    let id = UUID()
    let type: BlockType
    let content: String
    let language: String?
    let isClosed: Bool
    enum BlockType { case text, code }
}

struct CodeBlockView: View {
    let code: String
    let language: String
    let isClosed: Bool
    @State private var isCopied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.lowercased())
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(.gray)
                if !isClosed { ProgressView().scaleEffect(0.5).padding(.leading, 4) }
                Spacer()
                Button(action: {
                    UIPasteboard.general.string = code
                    withAnimation { isCopied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { isCopied = false } }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? "已复制" : "复制")
                    }.font(.system(size: 11)).foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8).background(Color.black.opacity(0.4))
            Divider().background(Color.gray.opacity(0.3))
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 13, design: .monospaced)).foregroundColor(.white)
                    .padding(12).textSelection(.enabled)
            }
        }
        .background(Color(UIColor.systemGray6).opacity(0.15))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3), lineWidth: 0.5))
    }
}
