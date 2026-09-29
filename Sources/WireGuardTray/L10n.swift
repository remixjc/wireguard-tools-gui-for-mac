import Foundation

/// 轻量中英双语本地化（不依赖 .lproj 资源编译，SwiftPM 构建零摩擦）
enum L10n {
    static let supportedLanguages = ["zh-Hans", "en"]

    /// 用户选择的语言（持久化），未选择时按系统语言推断
    static var language: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: "l10n.language"),
               supportedLanguages.contains(saved) {
                return saved
            }
            return defaultLanguage
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "l10n.language")
        }
    }

    static var isChinese: Bool { language == "zh-Hans" }

    static var defaultLanguage: String {
        for pref in Locale.preferredLanguages {
            if pref.hasPrefix("zh") { return "zh-Hans" }
            if pref.hasPrefix("en") { return "en" }
        }
        return "en"
    }

    static func t(_ key: String) -> String {
        let table = isChinese ? zh : en
        return table[key] ?? key
    }

    static func t(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }

    // MARK: - 中文

    private static let zh: [String: String] = [
        "status.connected": "已连接",
        "status.disconnected": "未连接",
        "status.connecting": "连接中…",
        "status.error": "错误",
        "action.start": "启动代理",
        "action.stop": "停止代理",
        "action.refresh": "刷新",
        "action.quit": "退出",
        "action.installPrivilege": "安装免密规则",
        "menu.tunnels": "隧道配置",
        "menu.noConfigs": "未找到配置",
        "menu.noConfigsHint": "将 <名称>.conf 放入 /etc/wireguard 后点击刷新",
        "menu.openConfigFolder": "打开 /etc/wireguard…",
        "menu.externalTunnel": "隧道由外部启动（配置不在 /etc/wireguard），已识别连接状态；停止将销毁接口",
        "menu.detail": "配置详情…",
        "menu.settings": "设置…",
        "settings.title": "设置",
        "settings.language": "语言",
        "settings.language.zh": "简体中文",
        "settings.language.en": "English",
        "settings.launchAtLogin": "登录时自动启动",
        "settings.launchHint": "将 App 放入应用程序目录后此选项生效",
        "settings.privilege": "提权",
        "settings.privilegeReady": "免密提权已就绪（sudoers 白名单已生效）",
        "settings.privilegeNotReady": "未配置免密提权：启动/停止时会弹出系统授权框",
        "settings.privilegeInstallHint": "执行下面命令可配置一次性免密（仅放行 wg-quick up/down）：",
        "settings.copyCommand": "复制安装命令",
        "settings.copied": "已复制 ✓",
        "settings.interfaceTitle": "PostUp/PostDown 网卡",
        "settings.interfaceNone": "不修改（保留原样）",
        "settings.interfaceHint": "隧道接口（utunN）编号重启后会变化，选择系统网卡可替换配置中的 dev 引用",
        "detail.title": "配置详情",
        "detail.sectionInterface": "Interface",
        "detail.sectionPeer": "Peer",
        "detail.postUp": "PostUp",
        "detail.postDown": "PostDown",
        "detail.interfacePicker": "网卡",
        "detail.applyInterface": "应用所选网卡",
        "detail.applied": "已更新配置（原文件已备份）",
        "detail.applyFailed": "应用失败：%@",
        "detail.backupHint": "修改前自动备份为 .conf.bak-<时间戳>",
        "detail.noSelection": "未选择配置",
        "detail.running": "运行中",
        "detail.stopped": "未运行",
        "detail.currentInterface": "当前引用",
        "detail.noReference": "PostUp/PostDown 中未引用 dev 接口",
        "error.start": "启动失败：%@",
        "error.stop": "停止失败：%@",
        "confirm.stopTitle": "停止隧道",
        "confirm.stopMessage": "确定要停止 %@ 吗？",
        "confirm.ok": "确定",
        "confirm.cancel": "取消",
        "common.interface": "接口",
        "common.endpoint": "Endpoint",
        "common.allowedIPs": "AllowedIPs",
        "common.address": "Address",
        "common.dns": "DNS",
        "common.mtu": "MTU",
    ]

    // MARK: - 英文

    private static let en: [String: String] = [
        "status.connected": "Connected",
        "status.disconnected": "Disconnected",
        "status.connecting": "Connecting…",
        "status.error": "Error",
        "action.start": "Start Tunnel",
        "action.stop": "Stop Tunnel",
        "action.refresh": "Refresh",
        "action.quit": "Quit",
        "action.installPrivilege": "Install Privilege Rule",
        "menu.tunnels": "Tunnels",
        "menu.noConfigs": "No configurations found",
        "menu.noConfigsHint": "Put <name>.conf in /etc/wireguard, then refresh",
        "menu.openConfigFolder": "Open /etc/wireguard…",
        "menu.externalTunnel": "Tunnel started externally (config not in /etc/wireguard); state detected. Stop will destroy the interface",
        "menu.detail": "Config Detail…",
        "menu.settings": "Settings…",
        "settings.title": "Settings",
        "settings.language": "Language",
        "settings.language.zh": "简体中文",
        "settings.language.en": "English",
        "settings.launchAtLogin": "Launch at login",
        "settings.launchHint": "Works after the app is in the Applications folder",
        "settings.privilege": "Privilege",
        "settings.privilegeReady": "Passwordless privilege ready (sudoers whitelist active)",
        "settings.privilegeNotReady": "Passwordless privilege not configured: system auth dialog will appear on start/stop",
        "settings.privilegeInstallHint": "Run the command below to configure one-time passwordless sudo (whitelists wg-quick up/down only):",
        "settings.copyCommand": "Copy Install Command",
        "settings.copied": "Copied ✓",
        "settings.interfaceTitle": "PostUp/PostDown Interface",
        "settings.interfaceNone": "Do not modify (keep as-is)",
        "settings.interfaceHint": "Tunnel interface (utunN) numbers change across reboots; pick a system interface to replace the dev reference in config",
        "detail.title": "Config Detail",
        "detail.sectionInterface": "Interface",
        "detail.sectionPeer": "Peer",
        "detail.postUp": "PostUp",
        "detail.postDown": "PostDown",
        "detail.interfacePicker": "Interface",
        "detail.applyInterface": "Apply Selected Interface",
        "detail.applied": "Config updated (original backed up)",
        "detail.applyFailed": "Apply failed: %@",
        "detail.backupHint": "Auto backup as .conf.bak-<timestamp> before modification",
        "detail.noSelection": "No config selected",
        "detail.running": "Running",
        "detail.stopped": "Stopped",
        "detail.currentInterface": "Current reference",
        "detail.noReference": "No dev interface reference in PostUp/PostDown",
        "error.start": "Start failed: %@",
        "error.stop": "Stop failed: %@",
        "confirm.stopTitle": "Stop Tunnel",
        "confirm.stopMessage": "Stop %@?",
        "confirm.ok": "OK",
        "confirm.cancel": "Cancel",
        "common.interface": "Interface",
        "common.endpoint": "Endpoint",
        "common.allowedIPs": "AllowedIPs",
        "common.address": "Address",
        "common.dns": "DNS",
        "common.mtu": "MTU",
    ]
}
