import SwiftUI

struct ChatView: View {
    // 空数组，不预设任何奇怪的角色
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            VStack {
                if messages.isEmpty {
                    Spacer()
                    Text("暂无会话记录")
                        .foregroundColor(.gray)
                        .font(.subheadline)
                    Spacer()
                } else {
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
                                                .background(Color.gray.opacity(0.2))
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
                                        Text("思考中...")
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
            .navigationTitle("会话")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    // 暂时留空，下一阶段接入真实的网络请求
    func sendMessage(_ text: String) async {
        guard !text.isEmpty else { return }
        await MainActor.run {
            messages.append(ChatMessage(role: "user", content: text))
            isLoading = true
        }
        
        // 暂时模拟一个最基础的响应，证明 UI 能动
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        await MainActor.run {
            messages.append(ChatMessage(role: "assistant", content: "已收到指令：\(text)"))
            isLoading = false
        }
    }
}