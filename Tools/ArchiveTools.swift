import Foundation
import ZIPFoundation

// MARK: - 解压
struct ExtractArchiveTool: AITool {
    static let name = "extract_archive"
    static let description = "解压 zip 压缩包到指定目录。压缩包必须已在沙箱中（例如用户上传的 uploads/xxx.zip）"
    static let parameters: [String: Any] = [
        "type": "object",
        "properties": [
            "archive_path": ["type": "string", "description": "压缩包在沙箱中的路径，如 uploads/game.zip"],
            "target_dir": ["type": "string", "description": "解压目标目录，留空则使用压缩包同名文件夹"]
        ],
        "required": ["archive_path"]
    ]

    static func execute(arguments: [String: Any]) async throws -> String {
        guard let archivePath = arguments["archive_path"] as? String else {
            return "错误：缺少 archive_path"
        }
        let vfs = VirtualFileSystem.shared

        let targetDir: String
        if let t = arguments["target_dir"] as? String, !t.isEmpty {
            targetDir = t
        } else {
            let nsPath = archivePath as NSString
            let name = nsPath.lastPathComponent
            let base = (name as NSString).deletingPathExtension
            let parent = nsPath.deletingLastPathComponent
            targetDir = parent.isEmpty ? base : "\(parent)/\(base)"
        }

        do {
            let archiveData = try vfs.readFileData(archivePath)

            // 写到临时文件
            let tmpZip = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".zip")
            try archiveData.write(to: tmpZip)
            defer { try? FileManager.default.removeItem(at: tmpZip) }

            guard let archive = Archive(url: tmpZip, accessMode: .read) else {
                return "无法读取压缩包（格式不支持或文件损坏）"
            }

            try vfs.createDirectory(targetDir)

            var count = 0
            for entry in archive {
                let vfsPath = targetDir + "/" + entry.path
                if entry.type == .directory {
                    try vfs.createDirectory(vfsPath)
                } else {
                    var data = Data()
                    _ = try archive.extract(entry) { chunk in
                        data.append(chunk)
                    }
                    try vfs.writeFileData(vfsPath, data: data)
                    count += 1
                }
            }

            return "解压完成，共 \(count) 个文件到 \(targetDir)"
        } catch {
            return "解压失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - 打包
struct CreateArchiveTool: AITool {
    static let name = "create_archive"
    static let description = "把沙箱内的目录或文件打包成 zip 压缩包"
    static let parameters: [String: Any] = [
        "type": "object",
        "properties": [
            "source_path": ["type": "string", "description": "要打包的源路径（文件或目录）"],
            "output_path": ["type": "string", "description": "输出的 zip 路径，如 uploads/result.zip"]
        ],
        "required": ["source_path", "output_path"]
    ]

    static func execute(arguments: [String: Any]) async throws -> String {
        guard let sourcePath = arguments["source_path"] as? String,
              let outputPath = arguments["output_path"] as? String else {
            return "错误：缺少 source_path 或 output_path"
        }
        let vfs = VirtualFileSystem.shared

        do {
            let srcNode = try vfs.node(at: sourcePath)
            let tmpZip = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".zip")
            defer { try? FileManager.default.removeItem(at: tmpZip) }

            guard let archive = Archive(url: tmpZip, accessMode: .create) else {
                return "无法创建压缩包"
            }

            if srcNode.isDirectory {
                try addDirectoryToArchive(archive: archive, node: srcNode, basePath: "")
            } else {
                let data = try vfs.readFileData(sourcePath)
                try addDataToArchive(archive: archive, data: data, path: srcNode.name)
            }

            // 把生成的 zip 写回 VFS
            let zipData = try Data(contentsOf: tmpZip)
            try vfs.writeFileData(outputPath, data: zipData)

            return "打包完成：\(outputPath)"
        } catch {
            return "打包失败：\(error.localizedDescription)"
        }
    }

    private static func addDirectoryToArchive(archive: Archive, node: VFSNode, basePath: String) throws {
        let currentPath = basePath.isEmpty ? node.name : "\(basePath)/\(node.name)"
        for (_, child) in node.children ?? [:] {
            if child.isDirectory {
                try addDirectoryToArchive(archive: archive, node: child, basePath: currentPath)
            } else if let data = child.content {
                try addDataToArchive(archive: archive, data: data, path: "\(currentPath)/\(child.name)")
            }
        }
    }

    private static func addDataToArchive(archive: Archive, data: Data, path: String) throws {
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(data.count),
            provider: { position, size in
                let start = Int(position)
                let end = min(start + size, data.count)
                return data.subdata(in: start..<end)
            }
        )
    }
}