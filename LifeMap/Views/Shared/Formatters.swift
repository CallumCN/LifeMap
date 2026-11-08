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
}
