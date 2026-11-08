import Foundation

enum Formatters {
    static func distance(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        if clamped < 60 {
            return Duration.seconds(clamped).formatted(.units(allowed: [.seconds], width: .abbreviated))
        }
        return Duration.seconds(clamped).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    static func clock(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: .minuteSecond))
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    static func speed(_ metersPerSecond: Double) -> String {
        Measurement(value: metersPerSecond, unit: UnitSpeed.metersPerSecond)
            .formatted(.measurement(width: .abbreviated, usage: .general))
    }

    /// "14:15-15:23, November 8th, 2026", or "2:15-3:23, …" on devices set to 12-hour time.
    /// Trips still in progress have no end time and show just the start.
    static func tripTitle(start: Date, end: Date?) -> String {
        let time = Date.FormatStyle().hour(.defaultDigits(amPM: .omitted)).minute()
        var title = start.formatted(time)
        if let end {
            title += "-" + end.formatted(time)
        }
        return "\(title), \(longDate(start))"
    }

    /// "November 8th, 2026"
    static func longDate(_ date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        let ordinal = ordinalFormatter.string(from: NSNumber(value: day)) ?? "\(day)"
        return "\(date.formatted(.dateTime.month(.wide))) \(ordinal), \(date.formatted(.dateTime.year()))"
    }

    private static let ordinalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter
    }()
}
