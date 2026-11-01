import AppKit
import IOKit
import IOKit.ps
import ToolbeltCore

/// One set of readings, for the menu and the System page.
struct SystemSnapshot {
    struct Battery {
        var percent: Int
        var status: String
        var health: Int?
        var cycles: Int?
    }

    var battery: Battery?
    var memoryUsed: Int64?
    var memoryTotal: Int64
    var cpuLoad: Double?
    var thermal: ProcessInfo.ThermalState
    var diskFree: Int64?
    var diskTotal: Int64?
    var uptime: TimeInterval

    /// Apple doesn't offer a public way to read the CPU temperature on Apple silicon,
    /// so this uses the system's own heat level instead.
    var thermalText: String {
        switch thermal {
        case .nominal: return "Normal"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Very hot"
        @unknown default: return "Unknown"
        }
    }

    var thermalDetail: String {
        switch thermal {
        case .nominal: return "Running cool"
        case .fair: return "A little warm, no slowdown"
        case .serious: return "Slowing down to cool off"
        case .critical: return "Slowing down a lot to cool off"
        @unknown default: return ""
        }
    }

    /// 0.25 per heat level, for a bar.
    var thermalFraction: Double {
        switch thermal {
        case .nominal: return 0.25
        case .fair: return 0.5
        case .serious: return 0.75
        case .critical: return 1
        @unknown default: return 0
        }
    }
}

/// Battery, memory, CPU, heat and disk readings.
final class SystemMonitor: NSObject {
    private var previousTicks: [UInt32]?
    private var cpuLoad: Double?
    private var sampler: Timer?

    func start() {
        // CPU load is the change between two readings, so take one every couple of seconds.
        sampleCPU()
        let sampler = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.sampleCPU() }
        RunLoop.main.add(sampler, forMode: .common)
        self.sampler = sampler
    }

    func snapshot() -> SystemSnapshot {
        let disk = diskSpace()
        return SystemSnapshot(battery: battery(), memoryUsed: memoryUsed(),
                              memoryTotal: Int64(ProcessInfo.processInfo.physicalMemory),
                              cpuLoad: cpuLoad, thermal: ProcessInfo.processInfo.thermalState,
                              diskFree: disk?.free, diskTotal: disk?.total,
                              uptime: ProcessInfo.processInfo.systemUptime)
    }

    func addItems(to menu: NSMenu) {
        let s = snapshot()
        menu.addInfo("System")
        if let battery = s.battery {
            menu.addInfo("Battery: \(battery.percent)% (\(battery.status))")
            var parts: [String] = []
            if let health = battery.health { parts.append("\(health)% health") }
            if let cycles = battery.cycles { parts.append("\(cycles) cycles") }
            if !parts.isEmpty { menu.addInfo("Battery: " + parts.joined(separator: " · ")) }
        } else {
            menu.addInfo("Battery: none (desktop Mac)")
        }
        if let used = s.memoryUsed {
            menu.addInfo("Memory: \(Formatting.bytes(used)) of \(Formatting.bytes(s.memoryTotal)) used")
        }
        menu.addInfo(s.cpuLoad.map { "CPU: \(Int(($0 * 100).rounded()))% busy" } ?? "CPU: measuring…")
        menu.addInfo("Heat: \(s.thermalText.lowercased())")
        if let free = s.diskFree, let total = s.diskTotal {
            menu.addInfo("Disk: \(Formatting.bytes(free)) free of \(Formatting.bytes(total))")
        }
        menu.addAction("Open Activity Monitor", target: self, action: #selector(openActivityMonitor))
    }

    // MARK: Battery

    private func battery() -> SystemSnapshot.Battery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
              let current = desc[kIOPSCurrentCapacityKey] as? Int,
              let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 else { return nil }
        let percent = Int((Double(current) / Double(max) * 100).rounded())
        let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
        let onPower = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        var status = charging ? "charging" : (onPower ? "plugged in" : "on battery")
        if !onPower, let minutes = desc[kIOPSTimeToEmptyKey] as? Int, minutes > 0 {
            status += ", \(Formatting.duration(TimeInterval(minutes * 60))) left"
        }

        var health: Int?
        var cycles: Int?
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            func read(_ key: String) -> Int? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? Int
            }
            // On Apple silicon "MaxCapacity" is a percentage; the raw value is in mAh.
            health = Formatting.batteryHealth(maxCapacity: read("AppleRawMaxCapacity") ?? read("MaxCapacity") ?? 0,
                                              designCapacity: read("DesignCapacity") ?? 0)
            cycles = read("CycleCount")
        }
        return SystemSnapshot.Battery(percent: percent, status: status, health: health, cycles: cycles)
    }

    // MARK: Memory and CPU

    private func memoryUsed() -> Int64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        // Roughly what Activity Monitor calls "Memory Used": app memory, wired and compressed.
        let page = Int64(vm_kernel_page_size)
        let appMemory = Int64(stats.internal_page_count) - Int64(stats.purgeable_count)
        return (appMemory + Int64(stats.wire_count) + Int64(stats.compressor_page_count)) * page
    }

    private func sampleCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3] // user, system, idle, nice
        if let previous = previousTicks {
            // Tick counters can wrap around, so subtract with overflow.
            let delta = zip(ticks, previous).map { Double($0 &- $1) }
            let total = delta.reduce(0, +)
            if total > 0 { cpuLoad = (total - delta[2]) / total }
        }
        previousTicks = ticks
    }

    // MARK: Disk

    private func diskSpace() -> (free: Int64, total: Int64)? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let free = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity else { return nil }
        return (free, Int64(total))
    }

    @objc func openActivityMonitor() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"),
                                           configuration: NSWorkspace.OpenConfiguration())
    }
}
