import AppKit
import WireGuardCore

/// 配置详情窗口：查看配置字段、PostUp/PostDown、选择网卡并应用写回（纯 AppKit）
@MainActor
final class DetailWindow: NSWindow {

    private let model: AppModel
    private var stack: NSStackView!
    private var titleLabel: NSTextField!
    private var stateLabel: NSTextField!
    private var interfacePopup: NSPopUpButton!
    private var applyButton: NSButton!
    private var referenceLabel: NSTextField!
    private var feedbackLabel: NSTextField!
    private var configView: NSTextView!
    private var lastConfigName: String?

    init(model: AppModel) {
        self.model = model
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        title = L10n.t("detail.title")
        isReleasedWhenClosed = false
        buildUI()
        reload()
    }

    // MARK: - UI 构建

    private func buildUI() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 560))

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        self.stack = stack

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        // 标题行
        let headRow = NSStackView()
        headRow.orientation = .horizontal
        headRow.spacing = 10
        let title = NSTextField(labelWithString: "")
        title.font = .boldSystemFont(ofSize: 18)
        titleLabel = title
        let state = NSTextField(labelWithString: "")
        stateLabel = state
        headRow.addArrangedSubview(title)
        headRow.addArrangedSubview(state)
        stack.addArrangedSubview(headRow)

        // 网卡选择行
        let pickRow = NSStackView()
        pickRow.orientation = .horizontal
        pickRow.spacing = 8
        let pickLabel = NSTextField(labelWithString: L10n.t("detail.interfacePicker") + ":")
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.target = self
        popup.action = #selector(interfaceChanged(_:))
        interfacePopup = popup
        let apply = NSButton(title: L10n.t("detail.applyInterface"), target: self, action: #selector(applyInterface(_:)))
        apply.bezelStyle = .rounded
        applyButton = apply
        pickRow.addArrangedSubview(pickLabel)
        pickRow.addArrangedSubview(popup)
        pickRow.addArrangedSubview(apply)
        stack.addArrangedSubview(pickRow)

        // 当前引用 / 提示 / 反馈
        let reference = NSTextField(wrappingLabelWithString: "")
        reference.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        reference.textColor = .secondaryLabelColor
        referenceLabel = reference
        stack.addArrangedSubview(reference)

        let hint = NSTextField(wrappingLabelWithString: L10n.t("detail.backupHint") + " · " + L10n.t("settings.interfaceHint"))
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(hint)

        let feedback = NSTextField(wrappingLabelWithString: "")
        feedback.font = .systemFont(ofSize: NSFont.smallSystemFontSize + 1)
        feedbackLabel = feedback
        stack.addArrangedSubview(feedback)

        // 配置内容
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.autoresizingMask = [.width]
        scroll.documentView = textView
        configView = textView
        stack.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true

        contentView = content
    }

    // MARK: - 数据刷新

    func reload() {
        guard let tunnel = model.selectedTunnel else {
            titleLabel.stringValue = L10n.t("detail.noSelection")
            stateLabel.stringValue = ""
            referenceLabel.stringValue = L10n.t("menu.noConfigsHint")
            interfacePopup.removeAllItems()
            configView.string = ""
            applyButton.isEnabled = false
            lastConfigName = nil
            return
        }

        let changed = tunnel.name != lastConfigName
        lastConfigName = tunnel.name

        titleLabel.stringValue = tunnel.name
        let running = model.isRunning && model.activeTunnelName == tunnel.name
        stateLabel.stringValue = running ? L10n.t("detail.running") : L10n.t("detail.stopped")
        stateLabel.textColor = running ? .systemGreen : .secondaryLabelColor

        // 网卡下拉（保持已选值）
        if changed {
            interfacePopup.removeAllItems()
            interfacePopup.addItem(withTitle: L10n.t("settings.interfaceNone"))
            interfacePopup.lastItem?.representedObject = ""
            for iface in model.interfaces {
                interfacePopup.addItem(withTitle: "\(iface.displayName) · \(iface.name)")
                interfacePopup.lastItem?.representedObject = iface.name
            }
            let current = PostUpEditor.referencedInterface(in: tunnel) ?? ""
            if let index = (0..<interfacePopup.numberOfItems).first(where: {
                (interfacePopup.item(at: $0)?.representedObject as? String) == current
            }) {
                interfacePopup.selectItem(at: index)
            } else {
                interfacePopup.selectItem(at: 0)
            }
            applyButton.isEnabled = !((interfacePopup.selectedItem?.representedObject as? String)?.isEmpty ?? true)
        }

        if let current = PostUpEditor.referencedInterface(in: tunnel) {
            referenceLabel.stringValue = L10n.t("detail.currentInterface") + ": \(current)"
        } else {
            referenceLabel.stringValue = L10n.t("detail.noReference")
        }

        configView.string = detailText(for: tunnel)
    }

    private func detailText(for tunnel: TunnelConfig) -> String {
        var out = ""
        if let section = tunnel.interfaceSection {
            out += "[\(section.name)]\n"
            for entry in section.entries {
                out += "\(entry.key) = \(entry.value)\n"
            }
            out += "\n"
        }
        for (index, peer) in tunnel.peerSections.enumerated() {
            out += "[Peer \(index + 1)]\n"
            for entry in peer.entries {
                out += "\(entry.key) = \(entry.value)\n"
            }
            out += "\n"
        }
        if !tunnel.postUpLines.isEmpty || !tunnel.postDownLines.isEmpty {
            for line in tunnel.postUpLines { out += "PostUp = \(line)\n" }
            for line in tunnel.postDownLines { out += "PostDown = \(line)\n" }
        }
        return out
    }

    // MARK: - 动作

    @objc private func interfaceChanged(_ sender: NSPopUpButton) {
        applyButton.isEnabled = !((sender.selectedItem?.representedObject as? String)?.isEmpty ?? true)
    }

    @objc private func applyInterface(_ sender: NSButton) {
        guard let tunnel = model.selectedTunnel else { return }
        let name = interfacePopup.selectedItem?.representedObject as? String ?? ""
        guard !name.isEmpty else { return }
        do {
            try model.applyInterface(name, to: tunnel)
            feedbackLabel.stringValue = L10n.t("detail.applied")
            feedbackLabel.textColor = .systemGreen
            reload()
        } catch {
            feedbackLabel.stringValue = L10n.t("detail.applyFailed", error.localizedDescription)
            feedbackLabel.textColor = .systemRed
        }
    }
}
