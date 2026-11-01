import Foundation

public enum Formatting {
    /// "4:05" or "1:02:03" for a countdown.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// "45 min", "2 h", "1 h 15 min".
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        let h = minutes / 60, m = minutes % 60
        switch (h, m) {
        case (0, _): return "\(m) min"
        case (_, 0): return "\(h) h"
        default: return "\(h) h \(m) min"
        }
    }

    /// "16.0 GB" using the decimal units Finder shows.
    public static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    /// Battery health as a percentage of its original capacity, capped at 100.
    public static func batteryHealth(maxCapacity: Int, designCapacity: Int) -> Int? {
        guard maxCapacity > 0, designCapacity > 0 else { return nil }
        return min(100, Int((Double(maxCapacity) / Double(designCapacity) * 100).rounded()))
    }
}
