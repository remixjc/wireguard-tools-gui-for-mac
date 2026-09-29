import Foundation
import Combine
import WireGuardCore

/// 应用全局状态：隧道列表、运行状态、网卡列表、操作编排
@MainActor
final class AppModel: ObservableObject {

    @Published var tunnels: [TunnelConfig] = []
    @Published var selectedName: String?
    @Published var status: TunnelStatus = .disconnected
    @Published var isBusy = false
    @Published var lastError: String?
    @Published var interfaces: [NetworkInterface] = []

    private var timer: Timer?

    init() {
        refreshAll()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
    }

    /// 停止状态轮询（应用退出时调用）
    func shutdown() {
        timer?.invalidate()
        timer = nil
    }

    var selectedTunnel: TunnelConfig? {
        tunnels.first { $0.name == selectedName }
    }

    /// 当前选中的隧道是否处于连接状态（wg show interfaces 命中）
    var isRunning: Bool {
        if case .connected = status { return true }
        return false
    }

    var activeTunnelName: String? {
        if case .connected(let interface) = status { return interface }
        return nil
    }

    var statusText: String {
        switch status {
        case .connected(let interface):
            return L10n.t("status.connected") + " · " + interface
        case .disconnected:
            return L10n.t("status.disconnected")
        case .error(let message):
            return L10n.t("status.error") + " · " + message
        }
    }

    // MARK: - 刷新

    func refreshAll() {
        refreshTunnels()
        refreshStatus()
        refreshInterfaces()
    }

    func refreshTunnels() {
        tunnels = ConfigParser.scanAll()
        if selectedName == nil || !tunnels.contains(where: { $0.name == selectedName }) {
            selectedName = tunnels.first?.name
        }
    }

    func refreshStatus() {
        let upInterfaces = CommandService.showInterfaces()
        // 1) 优先：选中的配置名恰好是活跃接口（标准 wg-quick 场景）
        if let name = selectedName, upInterfaces.contains(name) {
            status = .connected(interface: name)
        }
        // 2) macOS 上 wg-quick 创建的接口是系统分配的 utunN，与配置名不一致；
        //    只要系统里有 WireGuard 隧道在运行（无论由本应用还是外部启动），都识别为已连接
        else if let first = upInterfaces.first {
            status = .connected(interface: first)
        } else {
            status = .disconnected
        }
    }

    func refreshInterfaces() {
        interfaces = InterfaceService.allInterfaces()
    }

    // MARK: - 启停

    func toggle() async {
        if isRunning {
            await stopTunnel()
        } else {
            await startTunnel()
        }
    }

    func startTunnel() async {
        guard let name = selectedName, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await Task.detached(priority: .userInitiated) {
                try CommandService.up(configName: name)
            }.value
            lastError = nil
            refreshStatus()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stopTunnel() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            // 标准场景：配置存在于 /etc/wireguard → wg-quick down（完整执行 PostDown）
            if let name = selectedName, hasLocalConfig(name) {
                try await Task.detached(priority: .userInitiated) {
                    try CommandService.down(configName: name)
                }.value
            }
            // 外部启动的隧道（配置不在标准位置）：销毁 utun 接口断开隧道
            else if let active = activeTunnelName {
                try await Task.detached(priority: .userInitiated) {
                    try CommandService.destroyInterface(active)
                }.value
            }
            lastError = nil
            refreshStatus()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 标准配置目录中是否存在该配置（存在则用 wg-quick down 以获得完整 PostDown）
    private func hasLocalConfig(_ name: String) -> Bool {
        ConfigParser.standardSearchDirectories.contains { directory in
            FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(name).conf").path)
        }
    }

    /// 应用网卡选择到当前隧道配置：备份 + 原子写回
    func applyInterface(_ interfaceName: String, to config: TunnelConfig) throws {
        let updated = PostUpEditor.applyingInterface(interfaceName, to: config)
        try PostUpEditor.save(updated, backup: true)
        refreshTunnels()
        refreshStatus()
    }
}
