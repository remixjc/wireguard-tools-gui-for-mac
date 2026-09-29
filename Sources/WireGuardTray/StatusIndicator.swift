import AppKit
import SwiftUI
import WireGuardCore

/// 状态栏圆点图标：绿=已连接，灰=未连接，红=错误
enum StatusIndicator {

    static func image(for status: TunnelStatus) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        return NSImage(size: size, flipped: false) { rect in
            let color: NSColor
            switch status {
            case .connected:
                color = .systemGreen
            case .error:
                color = .systemRed
            case .disconnected:
                color = .systemGray
            }
            color.setFill()
            let d = min(rect.width, rect.height) * 0.62
            let inset = (rect.width - d) / 2
            NSBezierPath(ovalIn: NSRect(x: inset, y: inset, width: d, height: d)).fill()

            if case .connected = status {
                NSColor.white.setFill()
                let inner = d * 0.32
                let innerInset = (rect.width - inner) / 2
                NSBezierPath(ovalIn: NSRect(x: innerInset, y: innerInset, width: inner, height: inner)).fill()
            }
            return true
        }
    }
}
