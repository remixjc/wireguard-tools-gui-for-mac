import XCTest
@testable import WireGuardCore

final class ConfigParserTests: XCTestCase {

    func testParseBasicSections() {
        let content = """
        [Interface]
        PrivateKey = abc123
        Address = 10.0.0.2/32
        DNS = 1.1.1.1, 8.8.8.8

        [Peer]
        PublicKey = peerkey
        AllowedIPs = 0.0.0.0/0
        Endpoint = 203.0.113.10:51820
        """
        let sections = ConfigParser.parse(content: content)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].name, "Interface")
        XCTAssertEqual(sections[0].value(for: "PrivateKey"), "abc123")
        XCTAssertEqual(sections[1].name, "Peer")
        XCTAssertEqual(sections[1].value(for: "Endpoint"), "203.0.113.10:51820")
    }

    func testParseMultiplePostUpLines() {
        let content = """
        [Interface]
        PostUp = wg set %i private-key /etc/wireguard/privatekey
        PostUp = ip route add default dev utun8 table 51820
        PostDown = ip route del default dev utun8 table 51820
        """
        let sections = ConfigParser.parse(content: content)
        XCTAssertEqual(sections[0].values(for: "PostUp").count, 2)
        XCTAssertEqual(sections[0].values(for: "PostUp").first, "wg set %i private-key /etc/wireguard/privatekey")
        XCTAssertEqual(sections[0].value(for: "PostDown"), "ip route del default dev utun8 table 51820")
    }

    func testParseSkipsCommentsAndBlankLines() {
        let content = """
        # comment line
        [Interface]

        # inline comment only
        PrivateKey = key1
        """
        let sections = ConfigParser.parse(content: content)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].entries.count, 1)
        XCTAssertEqual(sections[0].value(for: "PrivateKey"), "key1")
    }

    func testSerializeRoundTrip() {
        let content = """
        [Interface]
        PrivateKey = key1
        Address = 10.0.0.2/32

        [Peer]
        PublicKey = pk
        AllowedIPs = 0.0.0.0/0
        """
        let sections = ConfigParser.parse(content: content)
        let serialized = ConfigParser.serialize(sections)
        let reparsed = ConfigParser.parse(content: serialized)
        XCTAssertEqual(sections, reparsed)
    }

    func testTunnelConfigAccessors() {
        let content = """
        [Interface]
        Address = 10.0.0.2/32
        DNS = 1.1.1.1
        PostUp = ip route add default dev utun8 table 51820

        [Peer]
        PublicKey = pk1
        AllowedIPs = 0.0.0.0/0
        Endpoint = 1.2.3.4:51820

        [Peer]
        PublicKey = pk2
        AllowedIPs = 10.0.0.0/24
        """
        let sections = ConfigParser.parse(content: content)
        let config = TunnelConfig(name: "wg0", path: "/etc/wireguard/wg0.conf", sections: sections)
        XCTAssertEqual(config.postUpLines, ["ip route add default dev utun8 table 51820"])
        XCTAssertEqual(config.postDownLines, [])
        XCTAssertEqual(config.endpoint, "1.2.3.4:51820")
        XCTAssertEqual(config.addresses, ["10.0.0.2/32"])
        XCTAssertEqual(config.dns, "1.1.1.1")
        XCTAssertEqual(config.peerSections.count, 2)
    }

    func testScanReturnsEmptyForMissingDirectory() {
        let bogus = URL(fileURLWithPath: "/nonexistent/wireguard-dir-xyz")
        XCTAssertTrue(ConfigParser.scan(directory: bogus).isEmpty)
    }

    func testLoadFromDisk() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wg-cfg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("wg0.conf")
        try "[Interface]\nPrivateKey = k\n[Peer]\nPublicKey = p\n"
            .write(to: url, atomically: true, encoding: .utf8)

        let config = try ConfigParser.load(from: url)
        XCTAssertEqual(config.name, "wg0")
        XCTAssertEqual(config.sections.count, 2)
    }
}
