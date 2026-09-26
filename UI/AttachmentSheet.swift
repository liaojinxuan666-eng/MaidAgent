import SwiftUI

struct AttachmentSheet: View {
    @Binding var isPresented: Bool
    var onSelectLocalFile: () -> Void
    var onSelectGitHub: () -> Void
    var onSelectWeb: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 顶部指示条
            Capsule()
                .frame(width: 40, height: 5)
                .foregroundColor(.gray.opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
            
            // 第一排：大卡片
            HStack(spacing: 12) {
                ActionCard(icon: "doc.badge.plus", title: "本地文件", action: {
                    isPresented = false
                    onSelectLocalFile()
                })
                ActionCard(icon: "chevron.left.forwardslash.chevron.right", title: "GitHub", action: {
                    isPresented = false
                    onSelectGitHub()
                })
                ActionCard(icon: "globe", title: "网页链接", action: {
                    isPresented = false
                    onSelectWeb()
                })
            }
            .padding(.horizontal)
            
            // 第二排：功能列表
            VStack(spacing: 0) {
                ListRow(icon: "puzzlepiece.extension", title: "沙箱插件", subtitle: "查看 AI 可用的所有工具")
                Divider().padding(.leading, 48)
                ListRow(icon: "target", title: "目标模式", subtitle: "持续执行至任务完成")
            }
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(16)
            .padding(.horizontal)
            
            Spacer()
        }
        .presentationDetents([.height(320)]) // 固定高度，类似 Kimi
        .presentationDragIndicator(.hidden)
        .background(Color.black)
    }
}

// 组件：大卡片
struct ActionCard: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(.primary)
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 90)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(16)
        }
    }
}

// 组件：列表行
struct ListRow: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.primary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body)
                Text(subtitle).font(.caption).foregroundColor(.gray)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
                .font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}