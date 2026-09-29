import XCTest
@testable import WireGuardCore

final class PostUpEditorTests: XCTestCase {

    func testExtractDevReference() {
        XCTAssertEqual(
            PostUpEditor.interfaceReferences(in: "ip route add default dev utun8 table 51820"),
            ["utun8"]
        )
        XCTAssertEqual(
            PostUpEditor.interfaceReferences(in: "ip route add default dev eth0 table 51820"),
            ["eth0"]
        )
        // `-o eth0` 形式（iptables 输出网卡）不属于 dev 引用，不应匹配
        XCTAssertEqual(
            PostUpEditor.interfaceReferences(in: "iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE"),
            []
        )
        XCTAssertEqual(
            PostUpEditor.interfaceReferences(in: "wg set %i private-key /etc/wireguard/key"),
            []
        )
        XCTAssertEqual(
            PostUpEditor.interfaceReferences(in: "echo hello"),
            []
        )
    }

    func testReplaceDevReference() {
        let line = "ip route add default dev utun8 table 51820"
        XCTAssertEqual(
            PostUpEditor.replacingInterface(in: line, with: "en0"),
            "ip route add default dev en0 table 51820"
        )
    }

    func testReplaceKeepsTemplateVariableIntact() {
        let line = "wg set %i private-key /etc/wireguard/key"
        XCTAssertEqual(
            PostUpEditor.replacingInterface(in: line, with: "en0"),
            line
        )
    }

    func testReplaceOnlyFirstOccurrence() {
        let line = "dev utun8 ip route add dev utun8"
        let result = PostUpEditor.replacingInterface(in: line, with: "en0")
        XCTAssertEqual(result, "dev en0 ip route add dev utun8")
    }

    func testReferencedInterface() {
        let config = makeConfig(postUp: "ip route add default dev utun8 table 51820", postDown: nil)
        XCTAssertEqual(PostUpEditor.referencedInterface(in: config), "utun8")
        XCTAssertTrue(PostUpEditor.hasInterfaceReference(in: config))

        let plain = makeConfig(postUp: "wg set %i private-key /etc/wireguard/key", postDown: nil)
        XCTAssertNil(PostUpEditor.referencedInterface(in: plain))
        XCTAssertFalse(PostUpEditor.hasInterfaceReference(in: plain))
    }

    // MARK: - networksetup 服务名模式

    func testExtractNetworkServiceReference() {
        XCTAssertEqual(
            PostUpEditor.references(in: "networksetup -setsocksfirewallproxy \"Ethernet\" 127.0.0.1 7890"),
            [PostUpReference(kind: .serviceName, value: "Ethernet")]
        )
        XCTAssertEqual(
            PostUpEditor.references(in: "networksetup -setsocksfirewallproxystate \"Wi-Fi\" off"),
            [PostUpReference(kind: .serviceName, value: "Wi-Fi")]
        )
        // 无引号形式
        XCTAssertEqual(
            PostUpEditor.references(in: "networksetup -setwebproxy Ethernet 127.0.0.1 8080"),
            [PostUpReference(kind: .serviceName, value: "Ethernet")]
        )
        // 非 networksetup 行仍走 dev 模式
        XCTAssertEqual(
            PostUpEditor.references(in: "ip route add default dev utun8 table 51820"),
            [PostUpReference(kind: .device, value: "utun8")]
        )
    }

    func testReplaceNetworkServiceReferenceKeepsQuotes() {
        let line = "networksetup -setsocksfirewallproxy \"Ethernet\" 127.0.0.1 7890"
        XCTAssertEqual(
            PostUpEditor.replacingReference(in: line, with: "Wi-Fi"),
            "networksetup -setsocksfirewallproxy \"Wi-Fi\" 127.0.0.1 7890"
        )
        let unquoted = "networksetup -setwebproxy Ethernet 127.0.0.1 8080"
        XCTAssertEqual(
            PostUpEditor.replacingReference(in: unquoted, with: "Wi-Fi"),
            "networksetup -setwebproxy Wi-Fi 127.0.0.1 8080"
        )
    }

    func testReferencedReturnsServiceName() {
        let config = makeConfig(
            postUp: "networksetup -setsocksfirewallproxy \"Ethernet\" 127.0.0.1 7890",
            postDown: "networksetup -setsocksfirewallproxystate \"Ethernet\" off"
        )
        XCTAssertEqual(
            PostUpEditor.referenced(in: config),
            PostUpReference(kind: .serviceName, value: "Ethernet")
        )
    }

    func testApplyingInterfaceWithServiceName() {
        let config = makeConfig(
            postUp: "networksetup -setsocksfirewallproxy \"Ethernet\" 127.0.0.1 7890",
            postDown: "networksetup -setsocksfirewallproxystate \"Ethernet\" off"
        )
        // 服务名替换：设备名 en0 → 服务名 Wi-Fi
        let updated = PostUpEditor.applyingInterface("en0", serviceName: "Wi-Fi", to: config)
        XCTAssertEqual(
            updated.postUpLines.first,
            "networksetup -setsocksfirewallproxy \"Wi-Fi\" 127.0.0.1 7890"
        )
        XCTAssertEqual(
            updated.postDownLines.first,
            "networksetup -setsocksfirewallproxystate \"Wi-Fi\" off"
        )
    }

    func testApplyingInterfaceMixedModes() {
        let config = makeConfig(
            postUp: "networksetup -setsocksfirewallproxy \"Ethernet\" 127.0.0.1 7890 && ip route add default dev utun8 table 51820",
            postDown: nil
        )
        let updated = PostUpEditor.applyingInterface("en1", serviceName: "Wi-Fi", to: config)
        XCTAssertEqual(
            updated.postUpLines.first,
            "networksetup -setsocksfirewallproxy \"Wi-Fi\" 127.0.0.1 7890 && ip route add default dev en1 table 51820"
        )
    }

    func testApplyingInterfaceUpdatesBothUpAndDown() {
        var config = makeConfig(
            postUp: "ip route add default dev utun8 table 51820",
            postDown: "ip route del default dev utun8 table 51820"
        )
        let updated = PostUpEditor.applyingInterface("en1", to: config)
        XCTAssertEqual(updated.postUpLines.first, "ip route add default dev en1 table 51820")
        XCTAssertEqual(updated.postDownLines.first, "ip route del default dev en1 table 51820")

        // 原配置不受影响
        XCTAssertEqual(config.postUpLines.first, "ip route add default dev utun8 table 51820")
    }

    func testSaveBacksUpAndWritesAtomically() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wg-save-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("wg0.conf")
        try "[Interface]\nPostUp = ip route add default dev utun8 table 51820\n"
            .write(to: url, atomically: true, encoding: .utf8)

        var config = try ConfigParser.load(from: url)
        config = PostUpEditor.applyingInterface("en2", to: config)
        try PostUpEditor.save(config, backup: true)

        // 原文件已更新
        let reloaded = try ConfigParser.load(from: url)
        XCTAssertEqual(reloaded.postUpLines.first, "ip route add default dev en2 table 51820")

        // 备份文件存在且保留原内容
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".conf.bak-") }
        XCTAssertEqual(backups.count, 1)
        let backupContent = try String(contentsOf: dir.appendingPathComponent(backups[0]), encoding: .utf8)
        XCTAssertTrue(backupContent.contains("dev utun8"))
    }

    // MARK: - helpers

    private func makeConfig(postUp: String?, postDown: String?) -> TunnelConfig {
        var entries: [WgKeyValue] = [WgKeyValue(key: "PrivateKey", value: "k")]
        if let postUp { entries.append(WgKeyValue(key: "PostUp", value: postUp)) }
        if let postDown { entries.append(WgKeyValue(key: "PostDown", value: postDown)) }
        let sections = [
            WgSection(name: "Interface", entries: entries),
            WgSection(name: "Peer", entries: [WgKeyValue(key: "PublicKey", value: "p")]),
        ]
        return TunnelConfig(name: "wg0", path: "/etc/wireguard/wg0.conf", sections: sections)
    }
}
