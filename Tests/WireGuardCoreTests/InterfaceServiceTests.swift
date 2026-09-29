import XCTest
@testable import WireGuardCore

final class InterfaceServiceTests: XCTestCase {

    func testFilteredExcludesLoopbackAndStale() {
        let names = ["lo0", "en0", "gif0", "stf0", "utun0", "bridge0", "awdl0", "en1"]
        let filtered = InterfaceService.filtered(names: names)
        XCTAssertEqual(filtered, ["en0", "utun0", "bridge0", "awdl0", "en1"])
    }

    func testFilteredDropsEmpty() {
        XCTAssertEqual(InterfaceService.filtered(names: ["", "en0", " "]), ["en0"])
    }

    func testParseHardwarePorts() {
        let text = """
        Hardware Port: Wi-Fi
        Device: en0
        Ethernet Address: aa:bb:cc:dd:ee:ff

        Hardware Port: Bluetooth PAN
        Device: en1
        Ethernet Address: 11:22:33:44:55:66

        Hardware Port: Thunderbolt Bridge
        Device: bridge0
        """
        let map = InterfaceService.parseHardwarePorts(text)
        XCTAssertEqual(map["en0"], "Wi-Fi")
        XCTAssertEqual(map["en1"], "Bluetooth PAN")
        XCTAssertEqual(map["bridge0"], "Thunderbolt Bridge")
        XCTAssertNil(map["lo0"])
    }

    func testParseHardwarePortsEmptyInput() {
        XCTAssertTrue(InterfaceService.parseHardwarePorts("").isEmpty)
        XCTAssertTrue(InterfaceService.parseHardwarePorts("no relevant content").isEmpty)
    }
}
