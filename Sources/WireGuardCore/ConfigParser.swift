import Foundation

public enum ConfigParserError: LocalizedError, Equatable {
    case unreadable(path: String)
    case notUTF8(path: String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let path):
            return "无法读取配置文件: \(path)"
        case .notUTF8(let path):
            return "配置文件不是 UTF-8 编码: \(path)"
        }
    }
}

/// wg-quick 配置文件（INI 风格）解析与序列化
public enum ConfigParser {

    /// 解析 wg-quick 配置文本为 section 列表
    /// - 规则：`[Section]` 开头新块；`key = value` 计入当前块；空行与 `#` 注释行忽略
    public static func parse(content: String) -> [WgSection] {
        var sections: [WgSection] = []
        var current: WgSection?

        func flush() {
            if let cur = current { sections.append(cur) }
            current = nil
        }

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if line.hasPrefix("["), line.hasSuffix("]") {
                flush()
                let name = String(line.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespaces)
                current = WgSection(name: name, entries: [])
                continue
            }

            if let eq = line.firstIndex(of: "=") {
                let key = line[..<eq].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: eq)...]
                    .trimmingCharacters(in: .whitespaces)
                current?.entries.append(WgKeyValue(key: key, value: value))
            }
            // 不含 "=" 的行在 wg 配置中无意义，跳过
        }
        flush()
        return sections
    }

    /// 将 section 列表序列化为 wg-quick 格式文本
    public static func serialize(_ sections: [WgSection]) -> String {
        var out = ""
        for section in sections {
            out += "[\(section.name)]\n"
            for entry in section.entries {
                out += "\(entry.key) = \(entry.value)\n"
            }
            out += "\n"
        }
        return out
    }

    /// 从磁盘加载一个配置文件为 TunnelConfig
    public static func load(from url: URL) throws -> TunnelConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ConfigParserError.unreadable(path: url.path)
        }
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            throw ConfigParserError.notUTF8(path: url.path)
        }
        let name = url.deletingPathExtension().lastPathComponent
        return TunnelConfig(name: name, path: url.path, sections: parse(content: content))
    }

    /// 扫描目录下所有 `.conf` 文件（默认 `/etc/wireguard`），按文件名排序
    public static func scan(directory: URL = URL(fileURLWithPath: "/etc/wireguard")) -> [TunnelConfig] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.pathExtension.lowercased() == "conf" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? load(from: $0) }
    }

    /// wg-quick 的完整配置搜索路径（与 wg-quick 脚本 CONFIG_SEARCH_PATHS 一致）
    public static var standardSearchDirectories: [URL] {
        ["/etc/wireguard", "/usr/local/etc/wireguard", "/opt/homebrew/etc/wireguard"]
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// 按 wg-quick 搜索路径扫描全部配置；同名配置优先取靠前目录，结果按名称排序
    public static func scanAll() -> [TunnelConfig] {
        var seen = Set<String>()
        var result: [TunnelConfig] = []
        for directory in standardSearchDirectories {
            for config in scan(directory: directory) where !seen.contains(config.name) {
                seen.insert(config.name)
                result.append(config)
            }
        }
        return result.sorted { $0.name < $1.name }
    }
}
