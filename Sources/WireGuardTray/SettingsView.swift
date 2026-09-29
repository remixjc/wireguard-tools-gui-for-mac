import AppKit
import ServiceManagement
import WireGuardCore

/// 设置窗口：语言、开机自启、提权状态（纯 AppKit）
@MainActor
final class SettingsWindow: NSWindow {

    private let model: AppModel
    private var stack: NSStackView!
    private var languagePopup: NSPopUpButton!
    private var launchCheckbox: NSButton!
    private var launchHint: NSTextField!
    private var privilegeStatus: NSTextField!
    private var commandField: NSTextField!
    private var installButton: NSButton!
    private var feedbackLabel: NSTextField!

    init(model: AppModel) {
        self.model = model
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        title = L10n.t("settings.title")
        isReleasedWhenClosed = false
        rebuild()
    }

    func rebuild() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        self.stack = stack

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
        ])

        // 语言
        stack.addArrangedSubview(sectionLabel(L10n.t("settings.language")))
        let langRow = NSStackView()
        langRow.orientation = .horizontal
        langRow.spacing = 8
        let langLabel = NSTextField(labelWithString: L10n.t("settings.language"))
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItem(withTitle: L10n.t("settings.language.zh"))
        popup.addItem(withTitle: L10n.t("settings.language.en"))
        popup.selectItem(at: L10n.isChinese ? 0 : 1)
        popup.target = self
        popup.action = #selector(languageChanged(_:))
        langRow.addArrangedSubview(langLabel)
        langRow.addArrangedSubview(popup)
        languagePopup = popup
        stack.addArrangedSubview(langRow)

        stack.addArrangedSubview(NSView.fixedHeight(1))

        // 开机自启
        let checkbox = NSButton(checkboxWithTitle: L10n.t("settings.launchAtLogin"), target: self, action: #selector(launchToggled(_:)))
        checkbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        launchCheckbox = checkbox
        stack.addArrangedSubview(checkbox)

        let hint = NSTextField(wrappingLabelWithString: L10n.t("settings.launchHint"))
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor
        launchHint = hint
        stack.addArrangedSubview(hint)

        stack.addArrangedSubview(NSView.fixedHeight(4))

        // 提权
        stack.addArrangedSubview(sectionLabel(L10n.t("settings.privilege")))
        let ready = CommandService.isSudoersReady()
        let status = NSTextField(wrappingLabelWithString: ready
            ? L10n.t("settings.privilegeReady")
            : L10n.t("settings.privilegeNotReady"))
        status.textColor = ready ? .systemGreen : .systemOrange
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize + 1)
        privilegeStatus = status
        stack.addArrangedSubview(status)

        let installHint = NSTextField(wrappingLabelWithString: L10n.t("settings.privilegeInstallHint"))
        installHint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        installHint.textColor = .secondaryLabelColor
        stack.addArrangedSubview(installHint)

        let command = NSTextField(wrappingLabelWithString: installCommand)
        command.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        command.isSelectable = true
        commandField = command
        stack.addArrangedSubview(command)

        let install = NSButton(title: L10n.t("settings.installCommand"), target: self, action: #selector(installPrivilege(_:)))
        install.bezelStyle = .rounded
        install.isEnabled = !ready
        installButton = install
        stack.addArrangedSubview(install)

        let feedback = NSTextField(wrappingLabelWithString: "")
        feedback.font = .systemFont(ofSize: NSFont.smallSystemFontSize + 1)
        feedbackLabel = feedback
        stack.addArrangedSubview(feedback)

        contentView = content
        contentView?.needsLayout = true
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 1)
        return label
    }

    private var installCommand: String {
        guard let wgQuick = CommandService.wgQuickPath else {
            return "brew install wireguard-tools"
        }
        return "sudo tee /etc/sudoers.d/wireguard-tray > /dev/null <<'EOF'\n"
            + "%admin ALL=(root) NOPASSWD: \(wgQuick) up *, \(wgQuick) down *\n"
            + "EOF\n"
            + "sudo chmod 440 /etc/sudoers.d/wireguard-tray\n"
            + "sudo visudo -c"
    }

    // MARK: - 动作

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        L10n.language = sender.indexOfSelectedItem == 0 ? "zh-Hans" : "en"
        rebuild()
    }

    @objc private func launchToggled(_ sender: NSButton) {
        let enabled = sender.state == .on
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchHint.stringValue = L10n.t("settings.launchHint")
            launchHint.textColor = .secondaryLabelColor
        } catch {
            launchHint.stringValue = error.localizedDescription
            launchHint.textColor = .systemRed
            launchCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }

    @objc private func installPrivilege(_ sender: NSButton) {
        sender.isEnabled = false
        sender.title = L10n.t("settings.installing")
        feedbackLabel.stringValue = ""
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                CommandService.installSudoers()
            }.value
            let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.exitCode == 0 {
                feedbackLabel.stringValue = L10n.t("settings.installSuccess")
                feedbackLabel.textColor = .systemGreen
                privilegeStatus.stringValue = L10n.t("settings.privilegeReady")
                privilegeStatus.textColor = .systemGreen
                sender.title = L10n.t("settings.installCommand")
                sender.isEnabled = false // 已就绪，无需再装
            } else {
                feedbackLabel.stringValue = L10n.t("settings.installFailed", output.isEmpty ? "exit \(result.exitCode)" : output)
                feedbackLabel.textColor = .systemRed
                sender.title = L10n.t("settings.installCommand")
                sender.isEnabled = true
            }
        }
    }
}

extension NSView {
    static func fixedHeight(_ height: CGFloat) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }
}
