import SwiftUI

struct SettingsView: View {
    @AppStorage("apiKey") private var apiKey: String = ""
    @AppStorage("baseURL") private var baseURL: String = "https://api.deepseek.com"
    @AppStorage("modelName") private var modelName: String = "deepseek-chat"
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("API 配置").foregroundColor(.gray)) {
                    SecureField("API Key", text: $apiKey)
                        .textContentType(.password)
                    
                    TextField("Base URL (例如 https://api.openai.com/v1)", text: $baseURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                    
                    TextField("模型名称 (例如 deepseek-chat)", text: $modelName)
                        .autocapitalization(.none)
                }
                
                Section(header: Text("GitHub 配置").foregroundColor(.gray)) {
                    Text("后续加入自动提交功能")
                        .foregroundColor(.gray)
                        .font(.caption)
                }
                
                Section {
                    Button("清空本地数据") {
                        apiKey = ""
                        baseURL = "https://api.deepseek.com"
                        modelName = "deepseek-chat"
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("设置")
            .background(Color.black.ignoresSafeArea())
        }
    }
}
