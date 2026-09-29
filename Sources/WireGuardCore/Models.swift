import Foundation

/// wg-quick 配置文件（INI 风格）中的一个键值对
public struct WgKeyValue: Equatable, Sendable {
    public let key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// 配置中的一个 `[Section]` 块（Interface / Peer）
public struct WgSection: Equatable, Sendable {
    public let name: String
    public var entries: [WgKeyValue]

    public init(name: String, entries: [WgKeyValue]) {
        self.name = name
        self.entries = entries
    }

    public func value(for key: String) -> String? {
        entries.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    public func values(for key: String) -> [String] {
        entries.filter { $0.key.caseInsensitiveCompare(key) == .orderedSame }.map(\.value)
    }
}

/// 一条完整的 WireGuard 隧道配置，对应 `/etc/wireguard/<name>.conf`
public struct TunnelConfig: Identifiable, Equatable, Sendable {
    public let name: String
    public let path: String
    public var sections: [WgSection]

    public init(name: String, path: String, sections: [WgSection]) {
        self.name = name
        self.path = path
        self.sections = sections
    }

    public var id: String { name }

    public var interfaceSection: WgSection? {
        sections.first { $0.name.caseInsensitiveCompare("Interface") == .orderedSame }
    }

    public var peerSections: [WgSection] {
        sections.filter { $0.name.caseInsensitiveCompare("Peer") == .orderedSame }
    }

    /// PostUp 命令列表（wg-quick 支持多行 PostUp）
    public var postUpLines: [String] {
        sections.flatMap { $0.values(for: "PostUp") }
    }

    /// PostDown 命令列表
    public var postDownLines: [String] {
        sections.flatMap { $0.values(for: "PostDown") }
    }

    public var endpoint: String? { peerSections.compactMap { $0.value(for: "Endpoint") }.first }
    public var addresses: [String] { interfaceSection?.values(for: "Address") ?? [] }
    public var dns: String? { interfaceSection?.value(for: "DNS") }
    public var mtu: String? { interfaceSection?.value(for: "MTU") }
    public var privateKey: String? { interfaceSection?.value(for: "PrivateKey") }
}

/// 系统网络接口（网卡）
public struct NetworkInterface: Identifiable, Equatable, Sendable {
    public let name: String
    public let displayName: String

    public init(name: String, displayName: String) {
        self.name = name
        self.displayName = displayName
    }

    public var id: String { name }
}

/// 隧道运行状态
public enum TunnelStatus: Equatable, Sendable {
    case disconnected
    case connected(interface: String)
    case error(message: String)
}
