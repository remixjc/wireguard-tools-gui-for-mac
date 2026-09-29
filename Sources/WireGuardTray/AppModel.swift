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
        tunnels = ConfigParser.scan()
        if selectedName == nil || !tunnels.contains(where: { $0.name == selectedName }) {
            selectedName = tunnels.first?.name
        }
    }

    func refreshStatus() {
        let upInterfaces = CommandService.showInterfaces()
        if let name = selectedName, upInterfaces.contains(name) {
            status = .connected(interface: name)
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
        guard let name = selectedName, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await Task.detached(priority: .userInitiated) {
                try CommandService.down(configName: name)
            }.value
            lastError = nil
            refreshStatus()
        } catch {
            lastError = error.localizedDescription
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
