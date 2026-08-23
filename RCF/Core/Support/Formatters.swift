import Foundation

/// Shared byte/date/number formatting (SwiftUI port of RN `formatBytes`, etc.).
/// Pure functions; usable from any executor.
nonisolated enum Formatters {
    /// Human-readable byte count: 1536 → "1.5 KB".
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    /// Relative date: "3 min ago".
    static func relative(_ date: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
    }

    /// Short date+time for tables: "Aug 23, 10:24".
    static var shortDateTime: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }

    /// Compact integer: 12_400 → "12.4K".
    static func compact(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = 1
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
