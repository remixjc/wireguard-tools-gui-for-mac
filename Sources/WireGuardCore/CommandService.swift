import Foundation

public enum CommandError: LocalizedError, Equatable {
    case brewNotFound
    case toolNotFound(String)
    case executionFailed(command: String, exitCode: Int32, output: String)
    case canceled

    public var errorDescription: String? {
        switch self {
        case .brewNotFound:
            return "未找到 Homebrew（brew），请先安装 Homebrew 与 wireguard-tools"
        case .toolNotFound(let tool):
            return "未找到命令: \(tool)，请先执行 brew install wireguard-tools"
        case .executionFailed(let command, let code, let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "命令失败 [\(command)] (exit \(code))\(trimmed.isEmpty ? "" : ": \(trimmed)")"
        case .canceled:
            return "操作已取消"
        }
    }
}

/// 执行 wg / wg-quick 命令的服务。
///
/// 路径解析策略：
/// 1. 通过 `brew --prefix` 定位（Apple Silicon 为 /opt/homebrew，Intel 为 /usr/local）
/// 2. 依次探测 bin / sbin / opt 下的 wg-quick
/// 3. 最后回退到 PATH（which）
///
/// 提权策略（wg-quick up/down 需要 root）：
/// 1. 优先 `sudo -n`：若已配置 sudoers 免密白名单则直接成功
/// 2. 兜底 AppleScript `with administrator privileges`：弹出系统授权框
public struct CommandService {

    private static let prefixLock = NSLock()
    private static var _brewPrefix: String?

    // MARK: - 路径定位

    public static var brewPrefix: String? {
        prefixLock.lock()
        defer { prefixLock.unlock() }
        if let cached = _brewPrefix { return cached }
        let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            let result = run(path, args: ["--prefix"])
            if result.exitCode == 0 {
                let prefix = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !prefix.isEmpty {
                    _brewPrefix = prefix
                    return prefix
                }
            }
        }
        return nil
    }

    public static var wgPath: String? {
        if let prefix = brewPrefix {
            for candidate in ["\(prefix)/bin/wg", "\(prefix)/sbin/wg", "\(prefix)/opt/wireguard-tools/bin/wg"] {
                if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
            }
        }
        return which("wg")
    }

    public static var wgQuickPath: String? {
        if let prefix = brewPrefix {
            for candidate in ["\(prefix)/bin/wg-quick", "\(prefix)/sbin/wg-quick", "\(prefix)/opt/wireguard-tools/sbin/wg-quick"] {
                if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
            }
        }
        return which("wg-quick")
    }

    // MARK: - 状态查询（无需 root）

    /// `wg show interfaces`：当前已 up 的接口名列表
    public static func showInterfaces() -> [String] {
        guard let wg = wgPath else { return [] }
        let result = run(wg, args: ["show", "interfaces"])
        guard result.exitCode == 0 else { return [] }
        return result.output.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// `wg show <iface>`：指定接口的完整状态文本
    public static func show(interface: String) -> String {
        guard let wg = wgPath else { return "" }
        let result = run(wg, args: ["show", interface])
        return result.exitCode == 0 ? result.output : ""
    }

    // MARK: - 启停（需要提权）

    public static func up(configName: String) throws {
        try toggle(configName: configName, up: true)
    }

    public static func down(configName: String) throws {
        try toggle(configName: configName, up: false)
    }

    /// 直接销毁隧道接口（`ifconfig <iface> destroy`，需 root）。
    /// 用于停止由外部启动、配置不在 /etc/wireguard 的隧道（无法用 wg-quick down 定位配置时）。
    public static func destroyInterface(_ iface: String) throws {
        let trimmed = iface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CommandError.executionFailed(command: "ifconfig destroy", exitCode: 1, output: "接口名为空")
        }
        let args = ["/sbin/ifconfig", trimmed, "destroy"]

        let sudoResult = run("/usr/bin/sudo", args: ["-n"] + args)
        if sudoResult.exitCode == 0 { return }

        let script = adminScript(args)
        let osa = run("/usr/bin/osascript", args: ["-e", script])
        guard osa.exitCode == 0 else {
            throw CommandError.executionFailed(
                command: "ifconfig \(trimmed) destroy",
                exitCode: osa.exitCode,
                output: osa.output
            )
        }
    }

    private static func toggle(configName: String, up: Bool) throws {
        guard let wgQuick = wgQuickPath else {
            throw CommandError.toolNotFound("wg-quick")
        }
        let action = up ? "up" : "down"
        let args = [wgQuick, action, configName]

        // 1) sudoers 免密路径
        let sudoResult = run("/usr/bin/sudo", args: ["-n"] + args)
        if sudoResult.exitCode == 0 { return }

        // 2) AppleScript 提权兜底
        let script = adminScript(args)
        let osa = run("/usr/bin/osascript", args: ["-e", script])
        guard osa.exitCode == 0 else {
            throw CommandError.executionFailed(
                command: "wg-quick \(action) \(configName)",
                exitCode: osa.exitCode,
                output: osa.output
            )
        }
    }

    /// 检查 sudoers 免密提权是否已配置（`sudo -n true` 直接成功表示可用）
    public static func isSudoersReady() -> Bool {
        run("/usr/bin/sudo", args: ["-n", "true"]).exitCode == 0
    }

    // MARK: - 基础执行

    static func run(_ executable: String, args: [String]) -> (output: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return ("\(error)", -1)
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (output, process.terminationStatus)
    }

    private static func which(_ tool: String) -> String? {
        let result = run("/usr/bin/which", args: [tool])
        guard result.exitCode == 0 else { return nil }
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    /// 生成 AppleScript 管理员提权脚本。
    /// 参数先各自做 shell 转义（`"..."`），再把整条命令嵌入 AppleScript 字符串时
    /// 转义其中的双引号与反斜杠，避免双重引号导致的 -2740 语法错误。
    private static func adminScript(_ args: [String]) -> String {
        let command = args.map(shellEscaped).joined(separator: " ")
        var escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }

    private static func shellEscaped(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
