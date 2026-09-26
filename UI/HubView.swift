import SwiftUI

struct HubView: View {
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("工具与扩展")) {
                    NavigationLink(destination: LibraryView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "books.vertical.fill")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            Text("资料库")
                        }
                    }
                    HStack {
                        Image(systemName: "puzzlepiece.extension")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        Text("插件管理")
                        Spacer()
                        Text("敬请期待").font(.caption).foregroundColor(.gray)
                    }
                }

                Section(header: Text("关于")) {
                    Text("PocketCode 正在持续进化中...")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .navigationTitle("探索")
        }
    }
}