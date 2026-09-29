# WireGuard Tray

> 一个轻量级 macOS 状态栏应用，为通过 Homebrew 安装的
> [wireguard-tools](https://formulae.brew.sh/formula/wireguard-tools)（`wg` / `wg-quick`）
> 提供图形界面：状态显示、一键启停、配置查看，以及 PostUp/PostDown 网卡（接口）编辑。

与 App Store 的 WireGuard 客户端不同，**本工具完整支持配置文件中的 `PostUp` / `PostDown` 钩子**——
这是 `wg-quick` 独有的能力（如连接时自动设置 SOCKS 代理、路由规则），官方 App 不会执行这些脚本。

[English](README.en.md) | **中文**（默认）

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-brightgreen)

---

## 目录

- [功能特性](#功能特性)
- [前置准备（必读）](#前置准备必读)
  - [1. 安装 Homebrew](#1-安装-homebrew)
  - [2. 安装 wireguard-tools](#2-安装-wireguard-tools)
  - [3. 创建 WireGuard 配置文件](#3-创建-wireguard-配置文件)
  - [4. 测试隧道能否启动](#4-测试隧道能否启动)
- [安装 WireGuard Tray](#安装-wireguard-tray)
  - [方式一：构建](#方式一构建)
  - [方式二：下载 Release](#方式二下载-release)
  - [配置免密提权（推荐）](#配置免密提权推荐)
- [使用指南](#使用指南)
  - [菜单栏](#菜单栏)
  - [配置详情窗口](#配置详情窗口)
  - [网卡编辑（PostUp/PostDown）](#网卡编辑postuppostdown)
  - [设置](#设置)
- [状态识别说明](#状态识别说明)
- [项目结构与开发](#项目结构与开发)
- [安全说明](#安全说明)
- [常见问题 FAQ](#常见问题-faq)
- [协议](#协议)

---

## 功能特性

- **状态栏指示点** — 绿点 / 灰点显示隧道已连接 / 未连接，每 2 秒自动刷新。
- **一键启动 / 停止** — 执行 `wg-quick up <名称>` / `wg-quick down <名称>`，完整执行
  PostUp / PostDown；默认走一次性免密 sudo 白名单，未配置时回退系统授权弹窗。
- **隧道列表** — 自动扫描 wg-quick 的全部配置搜索路径，菜单中一键切换并启动任意配置。
- **配置详情窗口** — 查看解析后的 `[Interface]` / `[Peer]` 字段与 `PostUp` / `PostDown` 行。
- **网卡编辑** — 同时支持两种引用模式：
  - `dev <iface>` 设备名模式（如 `ip route add default dev utun8 ...`）
  - `networksetup` 网络服务名模式（如 `networksetup -setsocksfirewallproxy "Ethernet" 127.0.0.1 7890`）
  
  从系统实时枚举网卡（`networksetup` + `ifconfig`）到下拉列表，替换配置中的引用，
  自动备份原文件（`*.conf.bak-<时间戳>`）并原子写回。
- **开机自启**（macOS 13+，`SMAppService`）。
- **中英双语界面**（简体中文 / English）。

## 前置准备（必读）

以下步骤在**任何图形界面之前**完成，确保命令行下隧道本身可以工作。

### 1. 安装 Homebrew

macOS 上使用 [Homebrew](https://brew.sh)（官方安装命令，需 Xcode 命令行工具支持）：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

安装完成后确认：

```bash
brew --version
```

### 2. 安装 wireguard-tools

```bash
brew install wireguard-tools
```

安装后确认可执行文件存在（Apple Silicon 在 `/opt/homebrew`，Intel 在 `/usr/local`）：

```bash
which wg wg-quick
# 预期（Apple Silicon）：
#   /opt/homebrew/bin/wg
#   /opt/homebrew/bin/wg-quick
```

> 若提示 `command not found`，检查 `brew doctor`，并确保 `/opt/homebrew/bin` 在 `PATH` 中。

### 3. 创建 WireGuard 配置文件

`wg-quick` 会按以下顺序搜索配置（与脚本内置的 `CONFIG_SEARCH_PATHS` 一致）：

```
/etc/wireguard            ← 系统默认
/usr/local/etc/wireguard  ← Intel Homebrew
/opt/homebrew/etc/wireguard  ← Apple Silicon Homebrew（本工具会扫描全部）
```

创建配置目录（选择你习惯的目录，推荐 Homebrew 的目录，无需 root 写权限）：

```bash
mkdir -p /opt/homebrew/etc/wireguard
```

以配置名 `fire` 为例，创建 `/opt/homebrew/etc/wireguard/fire.conf`：

```ini
[Interface]
PrivateKey = <你的私钥>
Address = 10.8.0.7/24
DNS = 223.5.5.5,1.1.1.1
# 连接成功后：把 macOS 系统网络服务 "Ethernet" 的 SOCKS 代理指向本地 7890 端口
PostUp = networksetup -setsocksfirewallproxy "Ethernet" 127.0.0.1 7890
# 断开后：关闭该 SOCKS 代理
PostDown = networksetup -setsocksfirewallproxystate "Ethernet" off

[Peer]
PublicKey = <对端公钥>
PresharedKey = <预共享密钥，可选>
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
Endpoint = <服务器地址>:51820
```

> **关于 PostUp/PostDown 的两种网卡写法**：
> - `dev <iface>`：引用的是**设备接口名**（如 `utun8`、`en0`）。macOS 上 WireGuard 隧道接口编号
>   （`utunN`）是系统动态分配的，重启后可能变化，写死会导致规则失效——这正是本工具网卡编辑
>   要解决的痛点。
> - `networksetup ... "服务名"`：引用的是**网络服务名**（如 `Ethernet`、`Wi-Fi`），
>   可在下拉列表中同样替换。

### 4. 测试隧道能否启动

先用命令行确认隧道可正常启停，再使用图形界面：

```bash
# 启动
sudo wg-quick up fire
# 查看接口（macOS 上接口名通常是 utunN，与配置名 fire 不一致，属正常现象）
wg show interfaces
# 停止（会完整执行 PostDown）
sudo wg-quick down fire
```

## 安装 WireGuard Tray

### 方式一：构建

需要 Xcode（或 Xcode 命令行工具 + Swift）：

```bash
git clone git@github.com:remixjc/wireguard-tools-gui-for-mac.git
cd wireguard-tools-gui-for-mac
./Scripts/build-app.sh
# => dist/WireGuardTray.app
```

### 方式二：下载 Release

直接下载已打包的 `WireGuardTray-0.1.0.zip`，解压后把 `WireGuardTray.app`
拖入「应用程序」文件夹。首次打开如遇 Gatekeeper 提示，右键 → 打开（本地 ad-hoc 签名）。

### 配置免密提权（推荐）

启动/停止隧道需要 root 权限。两种配置方式：

**在应用内（推荐）**：打开「设置 → 提权」，点击「安装命令」按钮，输入一次管理员密码，
自动写入白名单并校验。

**命令行脚本**：

```bash
sudo ./Scripts/install-sudoers.sh
```

脚本会在 `/etc/sudoers.d/wireguard-tray` 写入一条白名单，**仅放行**：

```
%admin ALL=(root) NOPASSWD: /opt/homebrew/bin/wg-quick up *, /opt/homebrew/bin/wg-quick down *
```

- 固定了 `wg-quick` 的绝对路径（防 PATH 劫持）
- 只放行 `up` / `down` 两个子命令，不放开任意命令
- 未配置时，应用每次启停会弹出系统授权框（功能不受影响，仅多一步确认）

启动应用后，菜单栏出现绿/灰指示点即成功。

## 使用指南

### 菜单栏

点击状态栏圆点打开菜单：

- **状态**：已连接（绿） / 未连接（灰）
- **启动 / 停止**：对当前选中的隧道执行 `wg-quick up` / `wg-quick down`
- **隧道列表**：切换当前配置（扫描全部搜索路径，同名配置按路径优先级去重）
- **配置详情**：打开详情窗口
- **设置**：语言、开机自启、提权
- **打开配置目录**：在访达中打开第一个存在的配置目录
- **退出**

> 若隧道由外部（如终端）启动，菜单会显示外部隧道状态，停止按钮同样可用
> （配置在搜索路径内走 `wg-quick down`，否则销毁接口兜底）。

### 配置详情窗口

- 顶部显示配置名与运行状态（**运行中** 绿色 / **未运行** 灰色，随状态轮询实时刷新）
- 中间为网卡选择器与「应用所选网卡」按钮
- 下方为解析后的完整配置内容（只读）

### 网卡编辑（PostUp/PostDown）

1. 打开「配置详情」
2. 下拉列表选择系统网卡（显示为「服务名 · 设备名」，如 `Ethernet · en0`）
3. 点击「应用所选网卡」

应用时会自动按引用类型替换：

| 配置中的引用 | 替换为 |
| --- | --- |
| `dev <iface>`（如 `dev utun8`） | 所选网卡的设备名（如 `en0`） |
| `networksetup ... "服务名"`（如 `"Ethernet"`） | 所选网卡的服务名（如 `Ethernet`） |

- 写回前自动备份：`fire.conf.bak-20260929-153000`
- 写回为原子操作（临时文件 + 替换）
- 同一行混合两种引用也会被正确处理

### 设置

- **语言**：简体中文 / English，即时切换
- **开机自启**：登录时自动启动（macOS 13+）
- **提权**：显示免密状态；未配置时可点击「安装命令」一键安装

## 状态识别说明

macOS 上 `wg-quick` 创建的是系统分配的接口（`utunN`），**接口名 ≠ 配置名**。
本工具按以下逻辑识别连接状态：

1. 选中的配置名恰好是活跃接口（标准 Linux 场景）
2. `wg-quick` 的记录文件（`/var/run/wireguard/<name>.name`）指向的接口活跃
3. 兜底：系统存在任意 WireGuard 隧道在运行（外部启动也能识别）

## 项目结构与开发

```
Sources/
  WireGuardCore/  纯逻辑库（可单元测试）：配置解析、命令执行、网卡枚举、PostUp 编辑
  WireGuardTray/  纯 AppKit 界面：状态栏、菜单、详情窗口、设置窗口、双语
Tests/
  WireGuardCoreTests/  23 个单元测试
Scripts/
  build-app.sh          构建并打包 .app（含 ad-hoc 签名）
  install-sudoers.sh   安装一次性免密 sudoers
  uninstall.sh         删除免密 sudoers
.github/workflows/build.yml  CI：每次 push 构建 + 测试 + 打包
```

构建与测试：

```bash
swift build -c release          # 编译
swift test                      # 运行全部测试
./Scripts/build-app.sh          # 生成 dist/WireGuardTray.app
```

## 安全说明

- sudoers 规则固定 `wg-quick` 绝对路径，仅放行 `up` / `down`，不执行任意命令
- 配置写回为原子操作，且总是先备份
- 本地构建为 ad-hoc 签名；如需对外分发，请用 Developer ID 重新签名
- 应用不收集任何数据，纯本地工具

## 常见问题 FAQ

**Q: 为什么不用 App Store 的 WireGuard 应用？**  
A: 官方 App 不会执行你的 `PostUp` / `PostDown` 脚本；`wg-quick` 会。本工具就是为这条
工作流提供图形界面。

**Q: `wg-quick up` 需要 root，安全吗？**  
A: 安全。提权规则通过 `sudoers.d` 限定为两个固定命令，UI 不会执行任意命令。

**Q: 配置放在哪里？**  
A: 本工具扫描 wg-quick 的全部搜索路径：`/etc/wireguard`、`/usr/local/etc/wireguard`、
`/opt/homebrew/etc/wireguard`。Homebrew（Apple Silicon）的配置通常放在
`/opt/homebrew/etc/wireguard/`。

**Q: 菜单栏显示已连接，但配置详情显示未运行？**  
A: 已修复：详情窗口按配置名精确判断，并随状态轮询实时刷新。升级到最新版本即可。

**Q: 为什么接口名是 `utun8` 而不是 `fire`？**  
A: macOS 上 `wg-quick` 使用用户态 `wireguard-go`，接口由系统动态分配为 `utunN`。
配置名与接口名的对应关系记录在 `/var/run/wireguard/fire.name`，状态识别依赖此机制。

## 协议

MIT — 见 [LICENSE](LICENSE)。
