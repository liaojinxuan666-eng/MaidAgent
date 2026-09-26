import SwiftUI

struct ChatView: View {
    @State private var messages: [ChatMessage] = [
        ChatMessage(role: "assistant", content: "主人，女仆已就绪。请下达代码修改指令。")
    ]
    @State private var inputText: String = ""
    @State private var isLoading = false
    
    // 从设置里读取 API Key 和 URL
    @AppStorage("apiKey") private var apiKey: String = ""
    @AppStorage("baseURL") private var baseURL: String = "https://api.deepseek.com"
    
    var body: some View {
        NavigationView {
            VStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(messages) { msg in
                                HStack {
                                    if msg.role == "user" {
                                        Spacer()
                                        Text(msg.content)
                                            .padding(12)
                                            .background(Color.blue.opacity(0.8))
                                            .foregroundColor(.white)
                                            .cornerRadius(16)
                                    } else {
                                        Text(msg.content)
                                            .padding(12)
                                            .background(Color.gray.opacity(0.3))
                                            .foregroundColor(.white)
                                            .cornerRadius(16)
                                        Spacer()
                                    }
                                }
                                .id(msg.id)
                            }
                            if isLoading {
                                HStack {
                                    ProgressView()
                                        .padding()
                                    Text("女仆正在思考...")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Spacer()
                                }
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _ in
                        if let lastId = messages.last?.id {
                            withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                        }
                    }
                }
                
                HStack {
                    TextField("输入指令...", text: $inputText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.horizontal)
                    
                    Button(action: {
                        let text = inputText
                        inputText = ""
                        Task { await sendMessage(text) }
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(inputText.isEmpty ? .gray : .blue)
                    }
                    .disabled(inputText.isEmpty || isLoading)
                    .padding(.trailing)
                }
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.6))
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("女仆 Agent")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    // 这里预留 API 调用逻辑（先写一个占位，后续填真实的网络请求）
    func sendMessage(_ text: String) async {
        guard !text.isEmpty else { return }
        await MainActor.run {
            messages.append(ChatMessage(role: "user", content: text))
            isLoading = true
        }
        
        // TODO: 接入真实的 API 请求（用你设置里填的 baseURL 和 apiKey）
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        
        await MainActor.run {
            messages.append(ChatMessage(role: "assistant", content: "收到指令：\(text)。因为现在的 API 梁子变阻器坏了，我暂时用模拟回复。主人快去设置里配一个新的 API 吧！"))
            isLoading = false
        }
    }
}