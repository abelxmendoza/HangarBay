import XCTest
@testable import DarkstarCore

final class MemoryResourcesTests: XCTestCase {
    private let vmStatSample = """
    Mach Virtual Memory Statistics: (page size of 16384 bytes)
    Pages free:                                10000.
    Pages active:                             400000.
    Pages inactive:                           200000.
    Pages speculative:                         10000.
    Pages wired down:                         100000.
    Pages occupied by compressor:             300000.
    """

    func testVMStatParserUsesHeaderPageSizeAndActivityMonitorConvention() {
        let snapshot = VMStatParser.parse(output: vmStatSample, totalBytes: 16_000_000_000, pressure: .warning, swapUsedBytes: 32_000_000)
        XCTAssertNotNil(snapshot)
        // used = (active 400000 + wired 100000 + compressor 300000) pages × 16384 B
        XCTAssertEqual(snapshot?.usedBytes, 800_000 * 16_384)
        XCTAssertEqual(snapshot?.compressedBytes, 300_000 * 16_384)
        XCTAssertEqual(snapshot?.availableBytes, 16_000_000_000 - 800_000 * 16_384)
        XCTAssertEqual(snapshot?.pressure, .warning)
        XCTAssertEqual(snapshot?.swapUsedBytes, 32_000_000)
    }

    func testVMStatParserRejectsGarbage() {
        XCTAssertNil(VMStatParser.parse(output: "not vm_stat output", totalBytes: 1, pressure: .unknown, swapUsedBytes: nil))
    }

    func testPressureParser() {
        XCTAssertEqual(MemoryPressureParser.parse(sysctlOutput: "1\n"), .normal)
        XCTAssertEqual(MemoryPressureParser.parse(sysctlOutput: "2"), .warning)
        XCTAssertEqual(MemoryPressureParser.parse(sysctlOutput: "4"), .critical)
        XCTAssertEqual(MemoryPressureParser.parse(sysctlOutput: "banana"), .unknown)
    }

    func testSwapParserUnits() {
        XCTAssertEqual(SwapUsageParser.parse(sysctlOutput: "vm.swapusage: total = 2048.00M  used = 30.72M  free = 2017.28M (encrypted)"), Int64(30.72 * 1_048_576))
        XCTAssertEqual(SwapUsageParser.parse(sysctlOutput: "vm.swapusage: total = 0.00M  used = 0.00M  free = 0.00M"), 0)
        XCTAssertNil(SwapUsageParser.parse(sysctlOutput: "no swap here"))
    }

    func testTopProcessesRollsHelpersIntoTheirApp() {
        let ps = """
          102400 /Applications/Firefox.app/Contents/MacOS/firefox
           51200 /Applications/Firefox.app/Contents/MacOS/plugin-container
           20480 /usr/sbin/syslogd
          204800 /Applications/UTM.app/Contents/MacOS/UTM
        """
        let top = TopProcessesParser.parse(output: ps, limit: 5)
        XCTAssertEqual(top.count, 3)
        XCTAssertEqual(top.first?.name, "UTM")
        XCTAssertEqual(top.first?.bytes, 204_800 * 1024)
        let firefox = top.first { $0.name == "Firefox" }
        XCTAssertEqual(firefox?.bytes, (102_400 + 51_200) * 1024)
        XCTAssertEqual(top.last?.name, "syslogd")
    }

    func testUTMConfigParserReadsMemorySize() {
        let plist = """
        <key>System</key>
        <dict>
            <key>Architecture</key><string>arm64</string>
            <key>MemorySize</key>
            <integer>8192</integer>
            <key>CPUCount</key><integer>6</integer>
        </dict>
        """
        XCTAssertEqual(UTMConfigParser.memorySizeMiB(configPlist: plist), 8192)
        XCTAssertNil(UTMConfigParser.memorySizeMiB(configPlist: "<dict></dict>"))
    }

    func testHeadroomRules() {
        let reservation: Int64 = 8_000_000_000
        // Already running: reservation is resident, starting is free.
        XCTAssertEqual(ResourceRules.runtimeHeadroom(pressure: .normal, availableBytes: 0, reservationBytes: reservation, vmRunning: true), .fits)
        XCTAssertEqual(ResourceRules.runtimeHeadroom(pressure: .critical, availableBytes: 0, reservationBytes: reservation, vmRunning: true), .tight)
        // Comfortable headroom.
        XCTAssertEqual(ResourceRules.runtimeHeadroom(pressure: .normal, availableBytes: 12_000_000_000, reservationBytes: reservation, vmRunning: false), .fits)
        // Exactly enough is tight, less is won't fit.
        XCTAssertEqual(ResourceRules.runtimeHeadroom(pressure: .normal, availableBytes: 8_500_000_000, reservationBytes: reservation, vmRunning: false), .tight)
        XCTAssertEqual(ResourceRules.runtimeHeadroom(pressure: .normal, availableBytes: 4_000_000_000, reservationBytes: reservation, vmRunning: false), .wontFit)
        // No reservation known: pressure alone decides, unknown stays unknown.
        XCTAssertEqual(ResourceRules.runtimeHeadroom(pressure: .warning, availableBytes: 0, reservationBytes: nil, vmRunning: false), .tight)
        XCTAssertEqual(ResourceRules.runtimeHeadroom(pressure: .unknown, availableBytes: 0, reservationBytes: nil, vmRunning: false), .unknown)
    }
}
