import Foundation

// MARK: - VFS 节点
final class VFSNode: Codable {
    var name: String
    var isDirectory: Bool
    var content: Data?              // 二进制统一存储
    var children: [String: VFSNode]?
    var createdAt: Date
    var modifiedAt: Date

    init(name: String, isDirectory: Bool, content: Data? = nil) {
        self.name = name
        self.isDirectory = isDirectory
        self.content = content
        self.children = isDirectory ? [:] : nil
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

// MARK: - VFS 错误
enum VFSError: Error, LocalizedError {
    case notFound(String)
    case notDirectory(String)
    case notFile(String)
    case alreadyExists(String)
    case pathTraversal(String)
    case invalidPath(String)
    case permissionDenied(String)
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let p): return "路径不存在: \(p)"
        case .notDirectory(let p): return "不是目录: \(p)"
        case .notFile(let p): return "不是文件: \(p)"
        case .alreadyExists(let p): return "已存在: \(p)"
        case .pathTraversal(let p): return "路径越界: \(p)"
        case .invalidPath(let p): return "非法路径: \(p)"
        case .permissionDenied(let p): return "权限拒绝: \(p)"
        case .decodeFailed(let p): return "无法以 UTF-8 解码: \(p)"
        }
    }
}

// MARK: - 虚拟文件系统
final class VirtualFileSystem {
    static let shared = VirtualFileSystem()

    private var root: VFSNode
    private let dbURL: URL
    private let queue = DispatchQueue(label: "vfs.queue", qos: .userInitiated)

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.dbURL = docs.appendingPathComponent("vfs.json")

        // 从磁盘加载
        if let data = try? Data(contentsOf: dbURL),
           let loaded = try? JSONDecoder().decode(VFSNode.self, from: data) {
            self.root = loaded
        } else {
            self.root = VFSNode(name: "/", isDirectory: true)
        }
    }

    // MARK: - 持久化
    private func persist() {
        guard let data = try? JSONEncoder().encode(root) else { return }
        let tmp = dbURL.appendingPathExtension("tmp")
        try? data.write(to: tmp, options: .atomic)
        try? FileManager.default.removeItem(at: dbURL)
        try? FileManager.default.moveItem(at: tmp, to: dbURL)
    }

    // MARK: - 路径解析与安全校验
    /// 把路径标准化为组件数组，禁止越界
    func normalizePath(_ path: String, cwd: String = "/") throws -> [String] {
        var components: [String]
        if path.hasPrefix("/") {
            components = []
        } else {
            components = cwd.split(separator: "/").map(String.init)
        }

        for comp in path.split(separator: "/") {
            let s = String(comp)
            if s.isEmpty || s == "." { continue }
            if s == ".." {
                if components.isEmpty {
                    throw VFSError.pathTraversal(path)
                }
                components.removeLast()
            } else {
                components.append(s)
            }
        }
        return components
    }

    /// 按路径查找节点
    func node(at path: String, cwd: String = "/") throws -> VFSNode {
        let comps = try normalizePath(path, cwd: cwd)
        var current = root
        for comp in comps {
            guard current.isDirectory, let child = current.children?[comp] else {
                throw VFSError.notFound(path)
            }
            current = child
        }
        return current
    }

    /// 查找父节点
    private func parentNode(of path: String, cwd: String = "/") throws -> (VFSNode, String) {
        let comps = try normalizePath(path, cwd: cwd)
        guard let last = comps.last else {
            throw VFSError.invalidPath(path)
        }
        let parentComps = Array(comps.dropLast())
        var current = root
        for comp in parentComps {
            guard current.isDirectory, let child = current.children?[comp] else {
                throw VFSError.notFound(path)
            }
            current = child
        }
        return (current, last)
    }

    // MARK: - 目录操作
    func listDir(_ path: String, cwd: String = "/") throws -> [String] {
        let node = try node(at: path, cwd: cwd)
        guard node.isDirectory else {
            throw VFSError.notDirectory(path)
        }
        return (node.children?.keys ?? [:].keys).sorted()
    }

    func createDirectory(_ path: String, cwd: String = "/") throws {
        let comps = try normalizePath(path, cwd: cwd)
        guard !comps.isEmpty else {
            throw VFSError.invalidPath(path)
        }

        var current = root
        for comp in comps {
            if let existing = current.children?[comp] {
                guard existing.isDirectory else {
                    throw VFSError.notDirectory(path)
                }
                current = existing
            } else {
                let newNode = VFSNode(name: comp, isDirectory: true)
                current.children?[comp] = newNode
                current = newNode
            }
        }
        persist()
    }

    func delete(_ path: String, cwd: String = "/") throws {
        let comps = try normalizePath(path, cwd: cwd)
        guard !comps.isEmpty else {
            throw VFSError.permissionDenied("不能删除根目录")
        }

        if comps.count == 1 {
            root.children?.removeValue(forKey: comps[0])
        } else {
            let (parent, lastName) = try parentNode(of: path, cwd: cwd)
            parent.children?.removeValue(forKey: lastName)
        }
        persist()
    }

    /// 判断路径是否存在
    func exists(_ path: String, cwd: String = "/") -> Bool {
        return (try? node(at: path, cwd: cwd)) != nil
    }

    /// 判断是否是目录
    func isDirectory(_ path: String, cwd: String = "/") throws -> Bool {
        return try node(at: path, cwd: cwd).isDirectory
    }

    // MARK: - 文件操作（二进制，底层统一）
    func readFileData(_ path: String, cwd: String = "/") throws -> Data {
        let node = try node(at: path, cwd: cwd)
        guard !node.isDirectory else {
            throw VFSError.notFile(path)
        }
        return node.content ?? Data()
    }

    func writeFileData(_ path: String, data: Data, cwd: String = "/") throws {
        let comps = try normalizePath(path, cwd: cwd)
        guard !comps.isEmpty else {
            throw VFSError.invalidPath(path)
        }

        if comps.count == 1 {
            let name = comps[0]
            if let existing = root.children?[name] {
                guard !existing.isDirectory else {
                    throw VFSError.notFile(path)
                }
                existing.content = data
                existing.modifiedAt = Date()
            } else {
                let newNode = VFSNode(name: name, isDirectory: false, content: data)
                root.children?[name] = newNode
            }
        } else {
            let (parent, lastName) = try parentNode(of: path, cwd: cwd)
            guard parent.isDirectory else {
                throw VFSError.notDirectory(path)
            }
            if let existing = parent.children?[lastName] {
                guard !existing.isDirectory else {
                    throw VFSError.notFile(path)
                }
                existing.content = data
                existing.modifiedAt = Date()
            } else {
                let newNode = VFSNode(name: lastName, isDirectory: false, content: data)
                parent.children?[lastName] = newNode
            }
        }
        persist()
    }

    // MARK: - 文件操作（文本便捷层）
    func readFileText(_ path: String, cwd: String = "/") throws -> String {
        let data = try readFileData(path, cwd: cwd)
        guard let text = String(data: data, encoding: .utf8) else {
            throw VFSError.decodeFailed(path)
        }
        return text
    }

    func writeFileText(_ path: String, text: String, cwd: String = "/") throws {
        guard let data = text.data(using: .utf8) else {
            throw VFSError.decodeFailed(path)
        }
        try writeFileData(path, data: data, cwd: cwd)
    }

    /// 判断是不是文本文件（简单启发式：能 UTF-8 解码）
    func isTextFile(_ path: String, cwd: String = "/") -> Bool {
        guard let data = try? readFileData(path, cwd: cwd) else { return false }
        return String(data: data, encoding: .utf8) != nil
    }

    // MARK: - 全局搜索
    func search(_ query: String) throws -> [(path: String, line: Int, content: String)] {
        var results: [(String, Int, String)] = []
        func walk(_ node: VFSNode, path: String) {
            if node.isDirectory {
                for (name, child) in node.children ?? [:] {
                    walk(child, path: path + "/" + name)
                }
            } else if let data = node.content,
                      let content = String(data: data, encoding: .utf8) {
                for (idx, line) in content.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    if line.localizedCaseInsensitiveContains(query) {
                        results.append((path, idx + 1, String(line)))
                    }
                }
            }
        }
        walk(root, path: "")
        return results
    }

    /// 列出所有文件路径（扁平）
    func allFilePaths() -> [String] {
        var paths: [String] = []
        func walk(_ node: VFSNode, path: String) {
            if node.isDirectory {
                for (name, child) in node.children ?? [:] {
                    walk(child, path: path + "/" + name)
                }
            } else {
                paths.append(path)
            }
        }
        walk(root, path: "")
        return paths
    }

    // MARK: - 快照支持
    func exportSnapshotData() throws -> Data {
        return try JSONEncoder().encode(root)
    }

    func restoreSnapshotData(_ data: Data) throws {
        let node = try JSONDecoder().decode(VFSNode.self, from: data)
        self.root = node
        persist()
    }

    // MARK: - 供 UI 展示
    func rootNode() -> VFSNode { root }
}
