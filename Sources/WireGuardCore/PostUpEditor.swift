import Foundation

public enum PostUpEditorError: LocalizedError, Equatable {
    case sourceMissing(path: String)
    case backupFailed(path: String)
    case writeFailed(path: String)

    public var errorDescription: String? {
        switch self {
        case .sourceMissing(let path):
            return "源文件不存在: \(path)"
        case .backupFailed(let path):
            return "备份失败: \(path)"
        case .writeFailed(let path):
            return "写入失败: \(path)"
        }
    }
}

/// 处理 PostUp/PostDown 中的网卡接口引用（`dev <iface>`）：
/// WireGuard 隧道接口（utunN）编号是动态分配的，重启后可能变化，
/// 导致写死接口名的路由规则失效。本模块负责提取与替换接口名。
public enum PostUpEditor {

    /// 匹配 `dev <iface>` 的正则（不匹配 `%i` 模板变量，因为 % 不在字符集内）
    private static let devPattern = #"(?i)\bdev\s+([a-zA-Z0-9_.\-]+)"#

    /// 从一条 PostUp/PostDown 命令行中提取引用的接口名
    public static func interfaceReferences(in line: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: devPattern) else { return [] }
        let ns = NSRange(line.startIndex..., in: line)
        return regex.matches(in: line, range: ns).compactMap { match in
            guard match.numberOfRanges == 2 else { return nil }
            let r = match.range(at: 1)
            guard let swiftRange = Range(r, in: line) else { return nil }
            return String(line[swiftRange])
        }
    }

    /// 将行中第一处 `dev <iface>` 替换为新接口名；无匹配则原样返回
    public static func replacingInterface(in line: String, with newName: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: devPattern) else { return line }
        let ns = NSRange(line.startIndex..., in: line)
        let mutable = NSMutableString(string: line)
        var replaced = false
        regex.enumerateMatches(in: line, options: [], range: ns) { match, _, stop in
            guard let match, !replaced else { return }
            // 只替换接口名部分（dev 之后），保留 "dev " 前缀
            if let nameRange = match.range(at: 1) as NSRange? {
                mutable.replaceCharacters(in: nameRange, with: newName)
                replaced = true
                stop.pointee = true
            }
        }
        return mutable as String
    }

    /// 配置 PostUp/PostDown 中引用的接口名（第一处），无引用返回 nil
    public static func referencedInterface(in config: TunnelConfig) -> String? {
        for line in config.postUpLines + config.postDownLines {
            if let first = interfaceReferences(in: line).first { return first }
        }
        return nil
    }

    /// 是否引用了接口（用于 UI 显示"需设置网卡"标记）
    public static func hasInterfaceReference(in config: TunnelConfig) -> Bool {
        referencedInterface(in: config) != nil
    }

    /// 将新接口名应用到配置的所有 PostUp/PostDown 行，返回修改后的副本
    public static func applyingInterface(_ iface: String, to config: TunnelConfig) -> TunnelConfig {
        var copy = config
        for si in copy.sections.indices {
            for ei in copy.sections[si].entries.indices {
                let entry = copy.sections[si].entries[ei]
                guard entry.key.caseInsensitiveCompare("PostUp") == .orderedSame
                        || entry.key.caseInsensitiveCompare("PostDown") == .orderedSame
                else { continue }
                copy.sections[si].entries[ei] = WgKeyValue(
                    key: entry.key,
                    value: replacingInterface(in: entry.value, with: iface)
                )
            }
        }
        return copy
    }

    /// 保存配置：先备份原文件（`<name>.conf.bak-<时间戳>`），再原子写回
    public static func save(_ config: TunnelConfig, backup: Bool = true) throws {
        let url = URL(fileURLWithPath: config.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PostUpEditorError.sourceMissing(path: url.path)
        }

        if backup {
            let stamp = DateFormatter.wgBackupStamp.string(from: Date())
            let backupURL = url.deletingPathExtension()
                .appendingPathExtension("conf.bak-\(stamp)")
            do {
                try FileManager.default.copyItem(at: url, to: backupURL)
            } catch {
                throw PostUpEditorError.backupFailed(path: url.path)
            }
        }

        let content = ConfigParser.serialize(config.sections)
        let tmpURL = url.appendingPathExtension("tmp")
        do {
            try content.write(to: tmpURL, atomically: true, encoding: .utf8)
        } catch {
            throw PostUpEditorError.writeFailed(path: url.path)
        }
        // 原子替换：成功则原路径被 tmp 覆盖
        _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
        if FileManager.default.fileExists(atPath: tmpURL.path) {
            try? FileManager.default.removeItem(at: tmpURL)
        }
    }
}

private extension DateFormatter {
    static let wgBackupStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
