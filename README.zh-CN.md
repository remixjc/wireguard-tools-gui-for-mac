# WireGuard Tray

一个轻量级 macOS 状态栏应用，用于管理通过 Homebrew 安装的
[wireguard-tools](https://formulae.brew.sh/formula/wireguard-tools)（`wg` / `wg-quick`）。

与 App Store 的 WireGuard 客户端不同，它完整支持配置文件中的 `PostUp` / `PostDown` 钩子，
并为它们提供了 UI。

## 功能

- **状态栏指示点** — 绿点/灰点显示隧道已连接/未连接，每 2 秒刷新。
- **一键启动/停止** — 执行 `wg-quick up <名称>` / `wg-quick down <名称>`，使用一次性免密
  sudo 白名单（未配置时回退到系统授权弹窗）。
- **隧道列表** — 扫描 `/etc/wireguard/*.conf`，在菜单中切换并启动任意配置。
- **配置详情窗口** — 查看解析后的 `[Interface]` / `[Peer]` 字段与 `PostUp` / `PostDown` 行。
- **PostUp/PostDown 网卡选择** — macOS 隧道接口（`utunN`）编号是动态分配的，重启后可能
  变化，导致写死 `dev utun8` 的规则失效。本应用通过 `networksetup` + `ifconfig` 枚举系统
  网卡到下拉列表，替换 `dev <iface>` 引用，自动备份原文件（`*.conf.bak-<时间戳>`）并原子写回。
- **开机自启**（macOS 13+，`SMAppService`）。
- **中英双语界面**。

## 环境要求

- macOS 13+
- [Homebrew](https://brew.sh)
- `brew install wireguard-tools`
- `/etc/wireguard/<名称>.conf` 配置（用 `sudo` 创建目录与文件）

## 构建

```bash
./Scripts/build-app.sh
# => dist/WireGuardTray.app
```

纯 AppKit 状态栏实现，无第三方依赖（仅 SwiftPM）。每次 push 由 GitHub Actions 构建并测试。

## 安装

1. 构建或下载 Release，把 `WireGuardTray.app` 复制到「应用程序」。
2. （推荐）安装一次性免密提权白名单：

   ```bash
   sudo ./Scripts/install-sudoers.sh
   ```

   该脚本在 `/etc/sudoers.d/wireguard-tray` 写入白名单，仅放行管理员的
   `wg-quick up <名称>` 与 `wg-quick down <名称>` 两个固定命令，不放开任意命令。
   未配置时，应用会在每次启停时弹出系统授权框。
   也可以从应用内「设置 → 提权」复制同样命令。

3. 启动应用，菜单栏出现绿/灰指示点。

## 使用

- 点击菜单栏圆点：状态、启动/停止、隧道列表、设置、配置详情。
- 「配置详情」→ 在下拉列表选择网卡 → 「应用所选网卡」：`PostUp` / `PostDown` 中所有
  `dev <iface>` 引用被替换，原文件自动备份，新配置原子写回。

## 安全说明

- sudoers 规则固定 `wg-quick` 绝对路径（防 PATH 劫持），仅放行 `up` / `down`。
- 配置写入为原子操作（临时文件 + rename），且总是先做带时间戳的备份。
- 本地构建为 ad-hoc 签名；GitHub Releases 分发时可让有 Apple 开发者账号的贡献者
  补 Developer ID 签名。

## FAQ

**Q: 为什么不用 App Store 的 WireGuard 应用？**  
A: 官方应用不会执行你的 `PostUp` / `PostDown` 脚本；`wg-quick` 会。本工具就是给这条
工作流做的 UI。

**Q: `wg-quick up` 需要 root，安全吗？**  
A: 安全。提权规则通过 `sudoers.d` 限定为两个固定命令，UI 不会执行任意命令。

## 协议

MIT — 见 [LICENSE](LICENSE)。
