import Foundation

// MARK: - Host memory resources (split-architecture design §9: know / show / manage)
//
// Darkstar's resource layer answers one user question — "can I run this
// now?" — from measurements, never guesses. This file holds the pure,
// testable half: parsers for macOS's own memory reporting (`vm_stat`,
// `sysctl`), the process-usage rollup, the UTM reservation reader, and the
// headroom rules. The app composes them through `MemoryProbe` on the same
// polling loop as the runtime probes.

// MARK: Memory pressure

/// macOS kernel memory pressure, as reported by
/// `kern.memorystatus_vm_pressure_level` (1 normal, 2 warning, 4 critical).
public enum MemoryPressure: Int, Equatable, Sendable {
    case unknown = 0
    case normal = 1
    case warning = 2
    case critical = 4

    public var label: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Elevated"
        case .critical: return "Critical"
        case .unknown: return "Unknown"
        }
    }
}

public enum MemoryPressureParser {
    public static func parse(sysctlOutput: String) -> MemoryPressure {
        let value = Int(sysctlOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return MemoryPressure(rawValue: value) ?? .unknown
    }
}

// MARK: Memory snapshot

/// One measurement of the host's memory state. `usedBytes` follows the
/// Activity Monitor convention (active + wired + compressor-occupied), so
/// the number Darkstar shows is the number the user can cross-check.
public struct MemorySnapshot: Equatable, Sendable {
    public let totalBytes: Int64
    public let usedBytes: Int64
    public let compressedBytes: Int64
    public let swapUsedBytes: Int64?
    public let pressure: MemoryPressure

    public init(totalBytes: Int64, usedBytes: Int64, compressedBytes: Int64, swapUsedBytes: Int64?, pressure: MemoryPressure) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.compressedBytes = compressedBytes
        self.swapUsedBytes = swapUsedBytes
        self.pressure = pressure
    }

    public var availableBytes: Int64 { max(0, totalBytes - usedBytes) }
    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(totalBytes)))
    }
}

public enum VMStatParser {
    /// Parses `vm_stat` output. The page size is read from the header line
    /// ("page size of 16384 bytes") rather than assumed — it differs across
    /// hardware generations.
    public static func parse(output: String, totalBytes: Int64, pressure: MemoryPressure, swapUsedBytes: Int64?) -> MemorySnapshot? {
        var pageSize: Int64 = 4096
        var pages: [String: Int64] = [:]
        for rawLine in output.split(separator: "\n") {
            let line = String(rawLine)
            if line.contains("page size of"), let size = firstInteger(in: line) {
                pageSize = size
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let valueText = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if let value = Int64(valueText) {
                pages[key] = value
            }
        }
        guard let active = pages["Pages active"],
              let wired = pages["Pages wired down"],
              let compressor = pages["Pages occupied by compressor"] else {
            return nil
        }
        return MemorySnapshot(
            totalBytes: totalBytes,
            usedBytes: (active + wired + compressor) * pageSize,
            compressedBytes: compressor * pageSize,
            swapUsedBytes: swapUsedBytes,
            pressure: pressure
        )
    }

    private static func firstInteger(in text: String) -> Int64? {
        var current = ""
        for character in text {
            if character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                break
            }
        }
        return Int64(current)
    }
}

public enum SwapUsageParser {
    /// Parses `sysctl vm.swapusage` output:
    /// "vm.swapusage: total = 2048.00M  used = 30.72M  free = 2017.28M (encrypted)"
    public static func parse(sysctlOutput: String) -> Int64? {
        guard let usedRange = sysctlOutput.range(of: "used = ") else { return nil }
        let rest = sysctlOutput[usedRange.upperBound...]
        let token = rest.split(separator: " ").first.map(String.init) ?? ""
        guard let value = Double(String(token.dropLast())) else { return nil }
        switch token.last {
        case "G": return Int64(value * 1_073_741_824)
        case "M": return Int64(value * 1_048_576)
        case "K": return Int64(value * 1024)
        default: return Int64(value)
        }
    }
}

// MARK: Top processes

public struct TopProcess: Equatable, Sendable, Identifiable {
    public let name: String
    public let bytes: Int64
    public var id: String { name }

    public init(name: String, bytes: Int64) {
        self.name = name
        self.bytes = bytes
    }
}

public enum TopProcessesParser {
    /// Parses `ps -axo rss=,comm=` output and rolls helper processes up into
    /// their owning app: anything inside a ".app" bundle counts toward the
    /// app's name, so a browser's twenty helpers read as one honest line.
    /// RSS from `ps` is in kibibytes.
    public static func parse(output: String, limit: Int) -> [TopProcess] {
        var totals: [String: Int64] = [:]
        for rawLine in output.split(separator: "\n") {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard let splitAt = line.firstIndex(where: { $0 == " " || $0 == "\t" }) else { continue }
            guard let rssKiB = Int64(line[..<splitAt]) else { continue }
            let path = line[line.index(after: splitAt)...].trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { continue }
            totals[appName(forExecutablePath: path), default: 0] += rssKiB * 1024
        }
        return totals
            .map { TopProcess(name: $0.key, bytes: $0.value) }
            .sorted { $0.bytes > $1.bytes }
            .prefix(max(0, limit))
            .map { $0 }
    }

    static func appName(forExecutablePath path: String) -> String {
        if let appRange = path.range(of: ".app/Contents/MacOS/") {
            let bundlePath = path[..<appRange.lowerBound]
            let bundleName = (bundlePath as NSString).lastPathComponent
            return bundleName.hasSuffix(".app") ? String(bundleName.dropLast(4)) : bundleName
        }
        if let appRange = path.range(of: ".app/") {
            let bundlePath = path[..<appRange.lowerBound]
            let bundleName = (bundlePath as NSString).lastPathComponent
            return bundleName.hasSuffix(".app") ? String(bundleName.dropLast(4)) : bundleName
        }
        return (path as NSString).lastPathComponent
    }
}

// MARK: UTM reservation

public enum UTMConfigParser {
    /// Reads the configured memory size (MiB) out of a UTM `config.plist`.
    /// The reservation is what the runtime *will* hold while running — the
    /// number the headroom verdict is computed against.
    public static func memorySizeMiB(configPlist: String) -> Int? {
        guard let keyRange = configPlist.range(of: "<key>MemorySize</key>") else { return nil }
        let rest = configPlist[keyRange.upperBound...]
        guard let open = rest.range(of: "<integer>"),
              let close = rest.range(of: "</integer>", range: open.upperBound..<rest.endIndex) else { return nil }
        let digits = rest[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(digits)
    }
}

// MARK: Headroom verdict

/// The one-word answer to "can I run the runtime now?" — a presentation
/// verdict over measured headroom, deliberately separate from the Phase 1
/// status taxonomy (READY / MISCONFIGURED / …). See design doc §9.
public enum HeadroomVerdict: Equatable, Sendable {
    case fits
    case tight
    case wontFit
    case unknown

    public var label: String {
        switch self {
        case .fits: return "FITS"
        case .tight: return "TIGHT"
        case .wontFit: return "WON'T FIT"
        case .unknown: return "UNKNOWN"
        }
    }
}

public enum ResourceRules {
    /// Headroom for starting the Linux runtime.
    ///
    /// - If the runtime is already running, its reservation is already
    ///   resident: starting costs nothing more, so the verdict is FITS
    ///   unless the kernel is already at critical pressure (TIGHT — the
    ///   machine is struggling with what it has).
    /// - Without a known reservation the verdict falls back to pressure
    ///   alone; without either, it is honestly UNKNOWN.
    /// - With a reservation: comfortable headroom (≥ 25% spare beyond the
    ///   reservation) is FITS, exactly-enough is TIGHT, less is WON'T FIT.
    public static func runtimeHeadroom(pressure: MemoryPressure, availableBytes: Int64, reservationBytes: Int64?, vmRunning: Bool) -> HeadroomVerdict {
        if vmRunning {
            return pressure == .critical ? .tight : .fits
        }
        guard let reservationBytes, reservationBytes > 0 else {
            switch pressure {
            case .normal: return .fits
            case .warning: return .tight
            case .critical: return .wontFit
            case .unknown: return .unknown
            }
        }
        if availableBytes >= reservationBytes + reservationBytes / 4 {
            return pressure == .critical ? .tight : .fits
        }
        if availableBytes >= reservationBytes {
            return .tight
        }
        return .wontFit
    }
}

// MARK: Probe composition

/// Composes the command executions behind the resource measurements.
/// Partial data degrades honestly: a failed pressure read yields
/// `.unknown`, a failed swap read yields `nil` — never a fabricated zero.
public struct MemoryProbe {
    private let runner: any CommandRunning

    public init(runner: any CommandRunning) {
        self.runner = runner
    }

    public func snapshot(totalBytes: Int64) -> MemorySnapshot? {
        guard let vmStat = try? runner.run(executable: "/usr/bin/vm_stat", arguments: [], timeout: 5),
              vmStat.isSuccess else { return nil }
        let pressure = (try? runner.run(executable: "/usr/sbin/sysctl", arguments: ["-n", "kern.memorystatus_vm_pressure_level"], timeout: 5))
            .map { MemoryPressureParser.parse(sysctlOutput: $0.stdout) } ?? .unknown
        let swap = (try? runner.run(executable: "/usr/sbin/sysctl", arguments: ["-n", "vm.swapusage"], timeout: 5))
            .flatMap { SwapUsageParser.parse(sysctlOutput: $0.stdout) }
        return VMStatParser.parse(output: vmStat.stdout, totalBytes: totalBytes, pressure: pressure, swapUsedBytes: swap)
    }

    public func topProcesses(limit: Int = 5) -> [TopProcess] {
        guard let output = try? runner.run(executable: "/bin/ps", arguments: ["-axo", "rss=,comm="], timeout: 5),
              output.isSuccess else { return [] }
        return TopProcessesParser.parse(output: output.stdout, limit: limit)
    }
}
