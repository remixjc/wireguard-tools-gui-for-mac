import AppKit
import Combine
import WireGuardCore

/// 应用入口与状态栏控制器（纯 AppKit，无 SwiftUI 宏依赖）
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private let model = AppModel()
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?
    private var detailWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        subscribeModel()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }

    // MARK: - 状态栏

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = StatusIndicator.image(for: model.status)
        item.button?.toolTip = "WireGuard Tray"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private func subscribeModel() {
        model.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.statusItem?.button?.image = StatusIndicator.image(for: status)
            }
            .store(in: &cancellables)
        model.$tunnels
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshDetailWindow() }
            .store(in: &cancellables)
        model.$selectedName
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshDetailWindow() }
            .store(in: &cancellables)
    }

    // MARK: - 菜单动作

    @objc private func toggleTunnel() {
        Task { await model.toggle() }
    }

    @objc private func selectTunnel(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        model.selectedName = name
        model.refreshStatus()
    }

    @objc private func openConfigFolder() {
        if let dir = ConfigParser.standardSearchDirectories.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) {
            NSWorkspace.shared.open(dir)
        } else {
            presentAlert(
                title: L10n.t("menu.openConfigFolder"),
                message: L10n.t("menu.noConfigsHint")
            )
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow(model: model)
        }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openDetail() {
        if detailWindow == nil {
            detailWindow = DetailWindow(model: model)
        }
        detailWindow?.center()
        detailWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshDetailWindow() {
        (detailWindow as? DetailWindow)?.reload()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - 菜单构建（每次打开时刷新）

extension AppDelegate: NSMenuDelegate {

    func menuNeedsUpdate(_ menu: NSMenu) {
        model.refreshAll()
        menu.removeAllItems()

        // 状态行
        let statusRow = NSMenuItem(title: model.statusText, action: nil, keyEquivalent: "")
        statusRow.isEnabled = false
        menu.addItem(statusRow)

        // 外部启动隧道的提示
        if model.isRunning && model.tunnels.isEmpty {
            let externalHint = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            externalHint.isEnabled = false
            externalHint.attributedTitle = NSAttributedString(string: L10n.t("menu.externalTunnel"), attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            ])
            menu.addItem(externalHint)
        }

        if let error = model.lastError {
            let errItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            errItem.isEnabled = false
            errItem.attributedTitle = NSAttributedString(string: error, attributes: [
                .foregroundColor: NSColor.systemRed,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            ])
            menu.addItem(errItem)
        }

        // 启停
        let toggleTitle = model.isRunning ? L10n.t("action.stop") : L10n.t("action.start")
        let toggle = NSMenuItem(title: toggleTitle, action: #selector(toggleTunnel), keyEquivalent: "")
        toggle.target = self
        // 有本地配置可启动；或系统已有隧道在运行（外部启动）可停止
        toggle.isEnabled = !model.isBusy && (model.selectedTunnel != nil || model.isRunning)
        menu.addItem(toggle)

        menu.addItem(.separator())

        // 隧道配置列表
        let tunnelsLabel = NSMenuItem(title: L10n.t("menu.tunnels"), action: nil, keyEquivalent: "")
        tunnelsLabel.isEnabled = false
        menu.addItem(tunnelsLabel)

        if model.tunnels.isEmpty {
            let noConfigs = NSMenuItem(title: L10n.t("menu.noConfigs"), action: nil, keyEquivalent: "")
            noConfigs.isEnabled = false
            menu.addItem(noConfigs)
            let openFolder = NSMenuItem(
                title: L10n.t("menu.openConfigFolder"),
                action: #selector(openConfigFolder), keyEquivalent: ""
            )
            openFolder.target = self
            menu.addItem(openFolder)
        } else {
            for tunnel in model.tunnels {
                let item = NSMenuItem(title: tunnel.name, action: #selector(selectTunnel(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = tunnel.name
                item.state = (model.selectedName == tunnel.name) ? .on : .off
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let detail = NSMenuItem(title: L10n.t("menu.detail"), action: #selector(openDetail), keyEquivalent: "")
        detail.target = self
        menu.addItem(detail)

        let settings = NSMenuItem(title: L10n.t("menu.settings"), action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: L10n.t("action.quit"), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }
}
