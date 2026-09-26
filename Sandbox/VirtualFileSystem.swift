import Foundation

// MARK: - VFS 节点
final class VFSNode: Codable {
    var name: String
    var isDirectory: Bool
    var content: String?          // 文件内容（仅文件节点）
    var children: [String: VFSNode]?  // 子节点（仅目录节点）
    var createdAt: Date
    var modifiedAt: Date
    
    init(name: String, isDirectory: Bool, content: String? = nil) {
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
    
    var errorDescription: String? {
        switch self {
        case .notFound(let p): return "路径不存在: \(p)"
        case .notDirectory(let p): return "不是目录: \(p)"
        case .notFile(let p): return "不是文件: \(p)"
        case .alreadyExists(let p): return "已存在: \(p)"
        case .pathTraversal(let p): return "路径越界: \(p)"
        case .invalidPath(let p): return "非法路径: \(p)"
        case .permissionDenied(let p): return "权限拒绝: \(p)"
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
        
        // 初始化根节点
        let rootNode = VFSNode(name: "/", isDirectory: true)
        
        // 从磁盘加载
        if let data = try? Data(contentsOf: dbURL),
           let loaded = try? JSONDecoder().decode(VFSNode.self, from: data) {
            self.root = loaded
        } else {
            self.root = rootNode
        }
    }
    
    // MARK: - 持久化
    private func persist() {
        guard let data = try? JSONEncoder().encode(root) else { return }
        // 原子写入：先写临时文件再重命名
        let tmp = dbURL.appendingPathExtension("tmp")
        try? data.write(to: tmp, options: .atomic)
        try? FileManager.default.removeItem(at: dbURL)
        try? FileManager.default.moveItem(at: tmp, to: dbURL)
    }
    
    // MARK: - 路径解析与安全校验
    /// 把路径标准化，并校验不越界
    func normalizePath(_ path: String, cwd: String = "/") throws -> [String] {
        // 绝对路径 vs 相对路径
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
                // 试图向上越界
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
            guard current.isDirectory,
                  let child = current.children?[comp] else {
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
            guard current.isDirectory,
                  let child = current.children?[comp] else {
                throw VFSError.notFound(path)
            }
            current = child
        }
        return (current, last)
    }
    
    // MARK: - 文件操作 API
    func listDir(_ path: String, cwd: String = "/") throws -> [String] {
        let node = try node(at: path, cwd: cwd)
        guard node.isDirectory else {
            throw VFSError.notDirectory(path)
        }
        return (node.children?.keys ?? [:].keys).sorted()
    }
    
    func readFile(_ path: String, cwd: String = "/") throws -> String {
        let node = try node(at: path, cwd: cwd)
        guard !node.isDirectory else {
            throw VFSError.notFile(path)
        }
        return node.content ?? ""
    }
    
    func writeFile(_ path: String, content: String, cwd: String = "/") throws {
        let comps = try normalizePath(path, cwd: cwd)
        guard !comps.isEmpty else {
            throw VFSError.invalidPath(path)
        }
        
        if comps.count == 1 {
            // 直接在根目录写
            let name = comps[0]
            if let existing = root.children?[name] {
                guard !existing.isDirectory else {
                    throw VFSError.notFile(path)
                }
                existing.content = content
                existing.modifiedAt = Date()
            } else {
                let newNode = VFSNode(name: name, isDirectory: false, content: content)
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
                existing.content = content
                existing.modifiedAt = Date()
            } else {
                let newNode = VFSNode(name: lastName, isDirectory: false, content: content)
                parent.children?[lastName] = newNode
            }
        }
        persist()
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
    
    /// 全局搜索文件内容
    func search(_ query: String) throws -> [(path: String, line: Int, content: String)] {
        var results: [(String, Int, String)] = []
        func walk(_ node: VFSNode, path: String) {
            if node.isDirectory {
                for (name, child) in node.children ?? [:] {
                    walk(child, path: path + "/" + name)
                }
            } else if let content = node.content {
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
    
    // MARK: - 快照支持
    func exportSnapshotData() throws -> Data {
        return try JSONEncoder().encode(root)
    }
    
    func restoreSnapshotData(_ data: Data) throws {
        let node = try JSONDecoder().decode(VFSNode.self, from: data)
        self.root = node
        persist()
    }
    
    // MARK: - 供 UI 展示的树结构
    func rootNode() -> VFSNode { root }
}