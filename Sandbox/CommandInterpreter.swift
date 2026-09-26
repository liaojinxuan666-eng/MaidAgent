import Foundation

// MARK: - 命令风险等级
enum CommandRisk: Int, Comparable {
    case safe = 0        // ls / cat / pwd / head / tail / echo
    case moderate = 1    // mkdir / touch / cp / mv
    case dangerous = 2   // rm / sed / awk / git
    case forbidden = 3   // su / sudo / chmod / sh / bash / curl / wget

    static func < (lhs: CommandRisk, rhs: CommandRisk) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// MARK: - 执行模式
enum ExecutionMode: String, CaseIterable {
    case auto = "全自动"
    case semiAuto = "半自动"
    case manual = "手动"
}

// MARK: - 命令执行结果
struct CommandResult {
    let output: String
    let exitCode: Int32
    let risk: CommandRisk
}

// MARK: - 审批请求
struct ApprovalRequest: Identifiable {
    let id = UUID()
    let command: String
    let risk: CommandRisk
    let description: String
}

// MARK: - 命令解释器
final class CommandInterpreter {
    static let shared = CommandInterpreter()

    private let vfs = VirtualFileSystem.shared

    /// 当前工作目录
    var cwd: String = "/"

    /// 当前执行模式
    var mode: ExecutionMode = .semiAuto

    /// 审批回调（由 UI 层设置）
    var approvalHandler: ((ApprovalRequest) async -> Bool)?

    private init() {}

    // MARK: - 命令风险表
    private func riskOf(_ command: String) -> CommandRisk {
        let cmd = command.trimmingCharacters(in: .whitespaces)
        let first = cmd.split(separator: " ").first.map(String.init)?.lowercased() ?? ""

        switch first {
        case "ls", "cat", "pwd", "head", "tail", "wc", "grep", "find", "echo":
            return .safe
        case "mkdir", "touch", "cp", "mv":
            return .moderate
        case "rm", "sed", "awk", "git":
            return .dangerous
        case "su", "sudo", "chmod", "chown", "sh", "bash", "zsh", "curl", "wget":
            return .forbidden
        default:
            return .forbidden
        }
    }

    // MARK: - 主入口
    /// 执行命令，返回结果。半自动/手动模式下可能会请求审批
    func execute(_ command: String) async throws -> CommandResult {
        let risk = riskOf(command)

        // 禁止命令直接拒绝
        if risk == .forbidden {
            return CommandResult(
                output: "拒绝执行: \(command)（该命令在 PocketCode 沙箱中不存在）",
                exitCode: 127,
                risk: risk
            )
        }

        // 是否需要审批
        let needsApproval: Bool
        switch mode {
        case .auto:
            needsApproval = false
        case .semiAuto:
            needsApproval = (risk == .dangerous)
        case .manual:
            needsApproval = (risk >= .moderate)
        }

        if needsApproval {
            guard let handler = approvalHandler else {
                return CommandResult(output: "需要审批但没有审批处理器", exitCode: 1, risk: risk)
            }
            let approved = await handler(ApprovalRequest(
                command: command,
                risk: risk,
                description: "AI 请求执行风险等级 \(risk) 的命令"
            ))
            if !approved {
                return CommandResult(output: "用户拒绝执行: \(command)", exitCode: 1, risk: risk)
            }
        }

        // 执行命令
        do {
            let output = try await dispatch(command)
            return CommandResult(output: output, exitCode: 0, risk: risk)
        } catch let err as VFSError {
            return CommandResult(output: err.localizedDescription, exitCode: 1, risk: risk)
        } catch {
            return CommandResult(output: error.localizedDescription, exitCode: 1, risk: risk)
        }
    }

    // MARK: - 命令分发
    private func dispatch(_ command: String) async throws -> String {
        let parts = tokenize(command)
        guard let cmd = parts.first?.lowercased() else { return "" }
        let args = Array(parts.dropFirst())

        switch cmd {
        case "pwd":   return cwd
        case "ls":    return try handleLs(args)
        case "cd":    return try handleCd(args)
        case "cat":   return try handleCat(args)
        case "mkdir": return try handleMkdir(args)
        case "touch": return try handleTouch(args)
        case "rm":    return try handleRm(args)
        case "echo":  return handleEcho(args)
        case "grep":  return try handleGrep(args)
        case "find":  return try handleFind(args)
        case "wc":    return try handleWc(args)
        case "head", "tail": return try handleHeadTail(cmd, args)
        default:
            return "命令未实现: \(cmd)"
        }
    }

    // MARK: - 简单分词（空格分割，支持引号）
    private func tokenize(_ command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuote: Character? = nil

        for ch in command {
            if let q = inQuote {
                if ch == q { inQuote = nil } else { current.append(ch) }
            } else if ch == "\"" || ch == "'" {
                inQuote = ch
            } else if ch == " " || ch == "\t" {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    // MARK: - 各命令实现
    private func handleLs(_ args: [String]) throws -> String {
        let path = args.last(where: { !$0.hasPrefix("-") }) ?? "."
        let items = try vfs.listDir(path, cwd: cwd)
        return items.isEmpty ? "(空目录)" : items.joined(separator: "  ")
    }

    private func handleCd(_ args: [String]) throws -> String {
        guard let target = args.first else {
            cwd = "/"
            return ""
        }
        _ = try vfs.node(at: target, cwd: cwd)
        let comps = try vfs.normalizePath(target, cwd: cwd)
        cwd = "/" + comps.joined(separator: "/")
        if cwd == "/" { cwd = "/" }
        return ""
    }

    private func handleCat(_ args: [String]) throws -> String {
        guard let path = args.first else { return "用法: cat <file>" }
        return try vfs.readFileText(path, cwd: cwd)
    }

    private func handleMkdir(_ args: [String]) throws -> String {
        let path = args.last(where: { !$0.hasPrefix("-") }) ?? ""
        guard !path.isEmpty else { return "用法: mkdir <dir>" }
        try vfs.createDirectory(path, cwd: cwd)
        return ""
    }

    private func handleTouch(_ args: [String]) throws -> String {
        guard let path = args.first else { return "用法: touch <file>" }
        do {
            _ = try vfs.readFileText(path, cwd: cwd)
        } catch {
            try vfs.writeFileText(path, text: "", cwd: cwd)
        }
        return ""
    }

    private func handleRm(_ args: [String]) throws -> String {
        let path = args.last(where: { !$0.hasPrefix("-") }) ?? ""
        guard !path.isEmpty else { return "用法: rm <path>" }
        try vfs.delete(path, cwd: cwd)
        return ""
    }

    private func handleEcho(_ args: [String]) -> String {
        // 支持 echo "text" > file
        if let redirectIdx = args.firstIndex(of: ">") {
            let content = args[..<redirectIdx].joined(separator: " ")
            let file = args[(redirectIdx + 1)...].joined(separator: " ")
            do {
                try vfs.writeFileText(file, text: content, cwd: cwd)
                return ""
            } catch {
                return "写入失败: \(error.localizedDescription)"
            }
        }
        return args.joined(separator: " ")
    }

    private func handleGrep(_ args: [String]) throws -> String {
        guard let pattern = args.first(where: { !$0.hasPrefix("-") }) else {
            return "用法: grep <pattern> [path]"
        }
        let results = try vfs.search(pattern)
        return results.map { "\($0.path):\($0.line): \($0.content)" }.joined(separator: "\n")
    }

    private func handleFind(_ args: [String]) throws -> String {
        let path = args.first ?? "."
        let node = try vfs.node(at: path, cwd: cwd)
        var results: [String] = []
        func walk(_ n: VFSNode, prefix: String) {
            results.append(prefix + n.name)
            if n.isDirectory {
                for (_, child) in n.children ?? [:] {
                    walk(child, prefix: prefix + n.name + "/")
                }
            }
        }
        walk(node, prefix: "")
        return results.joined(separator: "\n")
    }

    private func handleWc(_ args: [String]) throws -> String {
        guard let path = args.first else { return "用法: wc <file>" }
        let content = try vfs.readFileText(path, cwd: cwd)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).count
        let words = content.split(whereSeparator: { $0.isWhitespace }).count
        let chars = content.count
        return "\(lines)\t\(words)\t\(chars)\t\(path)"
    }

    private func handleHeadTail(_ cmd: String, _ args: [String]) throws -> String {
        let path = args.last ?? ""
        let n = 10
        let content = try vfs.readFileText(path, cwd: cwd)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        let selected = cmd == "head" ? lines.prefix(n) : lines.suffix(n)
        return selected.joined(separator: "\n")
    }
}