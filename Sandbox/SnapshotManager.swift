import Foundation

struct VFSSnapshot: Codable, Identifiable {
    let id: String              // 快照唯一标识（时间戳）
    let name: String            // 快照名称（例如："Before refactor"）
    let createdAt: Date
    let sizeInBytes: Int
}

final class SnapshotManager {
    static let shared = SnapshotManager()
    
    private let snapshotDir: URL
    private let maxSnapshots = 20  // 最多保留20个快照，防止撑爆App
    
    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        snapshotDir = docs.appendingPathComponent("snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: snapshotDir, withIntermediateDirectories: true)
    }
    
    // MARK: - 创建快照
    /// 从 VFS 导出数据并存为快照
    func createSnapshot(name: String) throws -> VFSSnapshot {
        let vfsData = try VirtualFileSystem.shared.exportSnapshotData()
        
        // 压缩一下，节省空间
        let compressed = try (vfsData as NSData).compressed(using: .zlib) as Data
        
        let id = String(Date().timeIntervalSince1970)
        let fileURL = snapshotDir.appendingPathComponent("\(id).json.gz")
        try compressed.write(to: fileURL)
        
        let snapshot = VFSSnapshot(
            id: id,
            name: name,
            createdAt: Date(),
            sizeInBytes: compressed.count
        )
        
        // 清理旧快照
        cleanupOldSnapshots()
        
        return snapshot
    }
    
    // MARK: - 回滚快照
    func restoreSnapshot(id: String) throws {
        let fileURL = snapshotDir.appendingPathComponent("\(id).json.gz")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw VFSError.notFound("快照 \(id) 不存在")
        }
        
        let compressed = try Data(contentsOf: fileURL)
        let decompressed = try (compressed as NSData).decompressed(using: .zlib) as Data
        
        try VirtualFileSystem.shared.restoreSnapshotData(decompressed)
    }
    
    // MARK: - 获取快照列表
    func listSnapshots() -> [VFSSnapshot] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: snapshotDir, includingPropertiesForKeys: nil) else {
            return []
        }
        
        return files
            .filter { $0.pathExtension == "gz" }
            .compactMap { url -> VFSSnapshot? in
                let id = url.deletingPathExtension().deletingPathExtension().lastPathComponent
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                let size = attrs?[.size] as? Int ?? 0
                let date = attrs?[.creationDate] as? Date ?? Date()
                return VFSSnapshot(id: id, name: "Snapshot \(id)", createdAt: date, sizeInBytes: size)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }
    
    // MARK: - 清理旧快照
    private func cleanupOldSnapshots() {
        let snapshots = listSnapshots()
        if snapshots.count > maxSnapshots {
            let toDelete = snapshots.dropFirst(maxSnapshots)  // 删除最旧的
            for snap in toDelete {
                let fileURL = snapshotDir.appendingPathComponent("\(snap.id).json.gz")
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }
}