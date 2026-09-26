import SwiftUI

struct ProjectView: View {
    // 每次进这个页面，都去拉取最新的 VFS 根节点
    @State private var rootNode: VFSNode = VirtualFileSystem.shared.rootNode()
    @State private var refreshID = UUID() // 用来强制刷新列表
    
    var body: some View {
        NavigationView {
            List {
                if let children = rootNode.children, !children.isEmpty {
                    ForEach(children.keys.sorted(), id: \.self) { key in
                        if let node = children[key] {
                            FileRow(node: node, basePath: "/\(key)")
                        }
                    }
                } else {
                    Text("沙箱工作区为空，去聊天页让 AI 写点代码吧")
                        .foregroundColor(.gray)
                        .font(.subheadline)
                }
            }
            .navigationTitle("沙箱项目")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // 刷新 VFS 状态
                        rootNode = VirtualFileSystem.shared.rootNode()
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }
}

// 统一的行渲染组件（支持文件和目录）
struct FileRow: View {
    let node: VFSNode
    let basePath: String
    
    var body: some View {
        if node.isDirectory {
            NavigationLink(destination: DirectoryView(directoryNode: node, basePath: basePath)) {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.blue)
                    Text(node.name)
                }
            }
        } else {
            NavigationLink(destination: FileDetailView(fileNode: node)) {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundColor(.gray)
                    Text(node.name)
                }
            }
        }
    }
}

// 递归目录视图
struct DirectoryView: View {
    let directoryNode: VFSNode
    let basePath: String
    
    var body: some View {
        List {
            if let children = directoryNode.children, !children.isEmpty {
                ForEach(children.keys.sorted(), id: \.self) { key in
                    if let child = children[key] {
                        FileRow(node: child, basePath: "\(basePath)/\(key)")
                    }
                }
            } else {
                Text("(空目录)")
                    .foregroundColor(.gray)
            }
        }
        .navigationTitle(directoryNode.name)
    }
}

// 文件详情（显示代码内容）
struct FileDetailView: View {
    let fileNode: VFSNode
    
    var body: some View {
        ScrollView {
            Text(fileNode.content ?? "(空文件)")
                .font(.system(.body, design: .monospaced))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(fileNode.name)
    }
}