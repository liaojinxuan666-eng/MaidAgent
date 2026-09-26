import SwiftUI

struct LibraryView: View {
    @StateObject private var store = ProjectStore.shared
    @State private var refreshID = UUID()
    @State private var selectedTab = "文件夹"

    private let tabs = ["推荐", "收藏", "文件夹", "图片", "全部"]

    var body: some View {
        VStack(spacing: 0) {
            // Tab 选择器（暂只实现“文件夹”，其他为占位）
            HStack(spacing: 6) {
                ForEach(tabs, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        Text(tab)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selectedTab == tab ? Color.white.opacity(0.15) : Color.clear)
                            .foregroundColor(selectedTab == tab ? .primary : .gray)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)

            if selectedTab == "文件夹" {
                folderList
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                        .padding(.top, 120)
                    Text("\(selectedTab) 功能开发中")
                        .foregroundColor(.gray)
                    Text("当前版本请使用「文件夹」查看上传的文件")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("资料库")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { refreshID = UUID() }) {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }

    private var folderList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                // 全局文件（没有归属项目的上传）
                if hasFiles(at: "/files") {
                    libraryFolder(name: "全局文件", path: "/files", icon: "tray.full")
                }

                // 每个项目一个文件夹
                ForEach(store.projects) { project in
                    libraryFolder(
                        name: project.name,
                        path: "/projects/\(project.id.uuidString)/files",
                        icon: "folder"
                    )
                }

                if store.projects.isEmpty && !hasFiles(at: "/files") {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                            .padding(.top, 80)
                        Text("还没有任何文件")
                            .foregroundColor(.gray)
                        Text("在聊天里点 + 上传文件，或创建项目后上传")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.horizontal)
        }
        .id(refreshID)
    }

    private func hasFiles(at path: String) -> Bool {
        let items = (try? VirtualFileSystem.shared.listDir(path)) ?? []
        return !items.isEmpty
    }

    @ViewBuilder
    private func libraryFolder(name: String, path: String, icon: String) -> some View {
        NavigationLink(destination: LibraryFolderView(displayName: name, basePath: path)) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                    .frame(width: 44, height: 44)
                    .background(Color.blue.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)
                    Text(fileCountText(at: path))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(14)
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func fileCountText(at path: String) -> String {
        let count = (try? VirtualFileSystem.shared.listDir(path))?.count ?? 0
        return count == 0 ? "空" : "\(count) 个文件"
    }
}

// MARK: - 项目资料库文件夹详情
struct LibraryFolderView: View {
    let displayName: String
    let basePath: String

    @State private var files: [String] = []

    var body: some View {
        List {
            if files.isEmpty {
                Text("暂无文件")
                    .foregroundColor(.gray)
            } else {
                ForEach(files, id: \.self) { name in
                    NavigationLink(destination: LibraryFileDetailView(filePath: basePath + "/" + name)) {
                        HStack(spacing: 12) {
                            Image(systemName: iconFor(name))
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name)
                                    .foregroundColor(.primary)
                                if let size = fileSizeText(basePath + "/" + name) {
                                    Text(size)
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadFiles() }
    }

    private func loadFiles() {
        files = (try? VirtualFileSystem.shared.listDir(basePath)) ?? []
    }

    private func iconFor(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.hasSuffix(".swift") { return "swift" }
        if lower.hasSuffix(".md") { return "doc.text" }
        if lower.hasSuffix(".zip") { return "archivebox" }
        if lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return "photo" }
        if lower.hasSuffix(".json") || lower.hasSuffix(".yml") || lower.hasSuffix(".yaml") { return "curlybraces" }
        return "doc"
    }

    private func fileSizeText(_ path: String) -> String? {
        guard let data = try? VirtualFileSystem.shared.readFileData(path) else { return nil }
        let bytes = data.count
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }
}

// MARK: - 文件详情
struct LibraryFileDetailView: View {
    let filePath: String
    @State private var content: String = ""
    @State private var isText = false
    @State private var showCopied = false

    var body: some View {
        ScrollView {
            if isText {
                Text(content)
                    .font(.system(size: 13, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("二进制文件，无法预览")
                        .foregroundColor(.gray)
                    Text(filePath)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .textSelection(.enabled)
                }
                .padding(.top, 120)
            }
        }
        .navigationTitle((filePath as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    UIPasteboard.general.string = filePath
                    withAnimation { showCopied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { showCopied = false } }
                }) {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                }
            }
        }
        .onAppear { loadContent() }
    }

    private func loadContent() {
        if let text = try? VirtualFileSystem.shared.readFileText(filePath) {
            content = text
            isText = true
        } else {
            isText = false
        }
    }
}