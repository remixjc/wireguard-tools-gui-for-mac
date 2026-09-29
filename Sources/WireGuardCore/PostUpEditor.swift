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

/// PostUp/PostDown 中网卡引用的类型
public enum PostUpReferenceKind: Equatable, Sendable {
    /// `dev utun8` —— 设备接口名
    case device
    /// `networksetup -setsocksfirewallproxy "Ethernet" ...` —— 网络服务名（Hardware Port 名）
    case serviceName
}

/// 一条 PostUp/PostDown 行中引用的网卡
public struct PostUpReference: Equatable, Sendable {
    public let kind: PostUpReferenceKind
    public let value: String

    public init(kind: PostUpReferenceKind, value: String) {
        self.kind = kind
        self.value = value
    }
}

/// 处理 PostUp/PostDown 中的网卡接口引用。
///
/// 两种常见写法：
/// 1. `dev <iface>`：如 `ip route add default dev utun8 ...`，引用的是设备接口名
/// 2. `networksetup -<子命令> "<服务名>" ...`：如
///    `networksetup -setsocksfirewallproxy "Ethernet" 127.0.0.1 7890`，
///    引用的是网络服务名（Hardware Port 名，如 Ethernet / Wi-Fi）
///
/// WireGuard 隧道接口（utunN）编号动态分配、重启后可能变化；本模块负责
/// 提取与替换这两种引用。
public enum PostUpEditor {

    /// 匹配 `dev <iface>` 的正则（不匹配 `%i` 模板变量，因为 % 不在字符集内）
    private static let devPattern = #"(?i)\bdev\s+([a-zA-Z0-9_.\-]+)"#

    /// 匹配 `networksetup -<子命令> ["']?<服务名>` 的正则
    private static let networksetupPattern = #"(?i)\bnetworksetup\s+(-[a-zA-Z][a-zA-Z0-9]*)\s+["']?([^"' \t]+)"#

    // MARK: - 引用提取

    /// 从一条 PostUp/PostDown 命令行中提取引用的网卡（networksetup 服务名优先，其次 dev 设备名）
    public static func references(in line: String) -> [PostUpReference] {
        if let match = firstMatch(networksetupPattern, in: line), match.numberOfRanges >= 3 {
            let value = group(match, at: 2, in: line)
            if !value.isEmpty {
                return [PostUpReference(kind: .serviceName, value: value)]
            }
        }
        return interfaceReferences(in: line).map { PostUpReference(kind: .device, value: $0) }
    }

    /// 从一条 PostUp/PostDown 命令行中提取 `dev <iface>` 形式的接口名
    public static func interfaceReferences(in line: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: devPattern) else { return [] }
        let ns = NSRange(line.startIndex..., in: line)
        return regex.matches(in: line, range: ns).compactMap { match in
            guard match.numberOfRanges == 2 else { return nil }
            return group(match, at: 1, in: line)
        }
    }

    // MARK: - 引用替换

    /// 将行中第一处网卡引用替换为新值（自动按 networksetup / dev 模式处理），无匹配则原样返回
    public static func replacingReference(in line: String, with newValue: String) -> String {
        if let match = firstMatch(networksetupPattern, in: line), match.numberOfRanges >= 3 {
            // 只替换服务名本体，保留原有引号
            return replacingGroup(match, at: 2, in: line, with: newValue)
        }
        return replacingInterface(in: line, with: newValue)
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

    // MARK: - 配置级操作

    /// 配置 PostUp/PostDown 中引用的网卡（第一处），无引用返回 nil
    public static func referenced(in config: TunnelConfig) -> PostUpReference? {
        for line in config.postUpLines + config.postDownLines {
            if let first = references(in: line).first { return first }
        }
        return nil
    }

    /// 配置 PostUp/PostDown 中引用的 `dev` 接口名（兼容旧接口），无引用返回 nil
    public static func referencedInterface(in config: TunnelConfig) -> String? {
        if let ref = referenced(in: config), ref.kind == .device {
            return ref.value
        }
        return nil
    }

    /// 是否引用了网卡（用于 UI 显示"需设置网卡"标记）
    public static func hasInterfaceReference(in config: TunnelConfig) -> Bool {
        referenced(in: config) != nil
    }

    /// 将新网卡应用到配置的所有 PostUp/PostDown 行：行内所有 networksetup 引用
    /// 替换为服务名、所有 dev 引用替换为设备名（serviceName 为 nil 时服务名退化为设备名），
    /// 返回修改后的副本
    public static func applyingInterface(
        _ iface: String,
        serviceName: String?,
        to config: TunnelConfig
    ) -> TunnelConfig {
        var copy = config
        for si in copy.sections.indices {
            for ei in copy.sections[si].entries.indices {
                let entry = copy.sections[si].entries[ei]
                guard entry.key.caseInsensitiveCompare("PostUp") == .orderedSame
                        || entry.key.caseInsensitiveCompare("PostDown") == .orderedSame
                else { continue }
                copy.sections[si].entries[ei] = WgKeyValue(
                    key: entry.key,
                    value: replacingAllReferences(in: entry.value, iface: iface, serviceName: serviceName)
                )
            }
        }
        return copy
    }

    /// 兼容旧签名：仅按设备名替换
    public static func applyingInterface(_ iface: String, to config: TunnelConfig) -> TunnelConfig {
        applyingInterface(iface, serviceName: nil, to: config)
    }

    /// 行内所有引用全量替换：networksetup → 服务名（保留引号样式），dev → 设备名
    private static func replacingAllReferences(in line: String, iface: String, serviceName: String?) -> String {
        var result = line
        result = replacingAllNetworksetupReferences(in: result, with: serviceName ?? iface)
        result = replacingAllDevReferences(in: result, with: iface)
        return result
    }

    private static func replacingAllDevReferences(in line: String, with newName: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: devPattern) else { return line }
        let ns = NSRange(line.startIndex..., in: line)
        let matches = regex.matches(in: line, range: ns)
        guard !matches.isEmpty else { return line }
        let mutable = NSMutableString(string: line)
        for match in matches.reversed() {
            mutable.replaceCharacters(in: match.range(at: 1), with: newName)
        }
        return mutable as String
    }

    private static func replacingAllNetworksetupReferences(in line: String, with newValue: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: networksetupPattern) else { return line }
        let ns = NSRange(line.startIndex..., in: line)
        let matches = regex.matches(in: line, range: ns)
        guard !matches.isEmpty else { return line }
        let mutable = NSMutableString(string: line)
        for match in matches.reversed() {
            // 只替换服务名本体，保留原有引号
            mutable.replaceCharacters(in: match.range(at: 2), with: newValue)
        }
        return mutable as String
    }

    // MARK: - 保存

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

    // MARK: - 正则辅助

    private static func firstMatch(_ pattern: String, in string: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = NSRange(string.startIndex..., in: string)
        return regex.firstMatch(in: string, options: [], range: ns)
    }

    private static func group(_ match: NSTextCheckingResult, at index: Int, in string: String) -> String {
        let ns = string as NSString
        let range = match.range(at: index)
        guard range.location != NSNotFound, range.location + range.length <= ns.length else { return "" }
        return ns.substring(with: range)
    }

    private static func replacingGroup(
        _ match: NSTextCheckingResult,
        at index: Int,
        in line: String,
        with replacement: String
    ) -> String {
        let mutable = NSMutableString(string: line)
        mutable.replaceCharacters(in: match.range(at: index), with: replacement)
        return mutable as String
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
