import Foundation

/// 系统网络接口枚举。
///
/// 数据来源：
/// - `networksetup -listallhardwareports`：物理硬件端口名（如 Wi-Fi → en0）
/// - `ifconfig -l`：全部接口（含 utunN 等虚拟接口，WireGuard 隧道即 utun 接口）
public struct InterfaceService {

    /// 全部网络接口：物理网卡（en*）优先，其余按序，过滤回环/无效接口
    public static func allInterfaces() -> [NetworkInterface] {
        let portNames = parseHardwarePorts(runText("networksetup", args: ["-listallhardwareports"]))
        let allNames = runText("ifconfig", args: ["-l"])
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        let names = filtered(names: allNames)

        var ordered = names.filter { $0.hasPrefix("en") }
        ordered.append(contentsOf: names.filter { !$0.hasPrefix("en") })

        return ordered.map { name in
            NetworkInterface(name: name, displayName: portNames[name] ?? name)
        }
    }

    /// 过滤规则（纯函数，便于单测）：排除回环与过时接口、纯空白项
    public static func filtered(names: [String]) -> [String] {
        let excluded: Set<String> = ["lo0", "gif0", "stf0"]
        return names
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !excluded.contains($0) }
    }

    /// 解析 `networksetup -listallhardwareports` 输出为 [设备名: 端口名]
    public static func parseHardwarePorts(_ text: String) -> [String: String] {
        var map: [String: String] = [:]
        var currentPort: String?
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Hardware Port:") {
                currentPort = String(line.dropFirst("Hardware Port:".count))
                    .trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Device:"), let port = currentPort {
                let device = String(line.dropFirst("Device:".count))
                    .trimmingCharacters(in: .whitespaces)
                if !device.isEmpty { map[device] = port }
            }
        }
        return map
    }

    private static func runText(_ executable: String, args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return ""
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
