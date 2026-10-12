//
//  MeasurementFormat.swift
//  ScreenBean
//
//  How measurements are shown and typed. Everything is stored in inches; the unit setting
//  (inches or centimeters) only changes how values are shown and read. Inches can be shown as
//  decimals ("23.125") or fractions to the nearest 16th ("23 1/8"); either can always be typed.
//  A unit typed after a number ("60 cm", "600 mm", "24 in") is always understood.
//

import Foundation

enum MeasurementFormat {
    /// Posted when `useFractions` changes, so open fields can redraw.
    static let didChange = Notification.Name("ScreenBean.MeasurementFormatDidChange")

    /// Fractions are rounded to this denominator.
    static let denominator = 16

    private static let key = "ScreenBean.UseFractions"
    private static let unitKey = "ScreenBean.MeasurementUnit"

    enum Unit: String {
        case inches, centimeters

        var unitsPerInch: Double { self == .inches ? 1 : 2.54 }
        var name: String { rawValue }
        var suffix: String { self == .inches ? "in" : "cm" }
    }

    /// The unit measurements are shown in. Values are stored in inches either way.
    static var unit: Unit {
        get { UserDefaults.standard.string(forKey: unitKey).flatMap(Unit.init(rawValue:)) ?? .inches }
        set {
            guard newValue != unit else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: unitKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    static var unitName: String { unit.name }
    static var unitSuffix: String { unit.suffix }
    /// Inches in one shown unit: 1 for inches, about 0.394 for centimeters.
    static var inchesPerUnit: Double { 1 / unit.unitsPerInch }

    /// Fractions only make sense in inches.
    static var showsFractions: Bool { useFractions && unit == .inches }

    static var useFractions: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set {
            guard newValue != useFractions else { return }
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// The step for steppers and scrubbing: one 16th in fraction mode, otherwise `decimalStep`.
    static func step(decimal decimalStep: Double) -> Double {
        if showsFractions { return 1.0 / Double(denominator) }
        // A tenth of a centimeter, in inches.
        return unit == .centimeters ? 0.1 / unit.unitsPerInch : decimalStep
    }

    /// Rounds to the nearest 16th.
    static func roundedToFraction(_ value: Double) -> Double {
        (value * Double(denominator)).rounded() / Double(denominator)
    }

    // MARK: - Formatting

    /// A length given in inches, written in the chosen unit and style, without the unit.
    static func string(_ value: Double) -> String {
        showsFractions ? fractionString(value) : decimalString(value * unit.unitsPerInch)
    }

    /// "23.5 in" or "59.69 cm".
    static func withUnit(_ value: Double) -> String { "\(string(value)) \(unitSuffix)" }

    /// "23.5 × 13.2 in" or "59.69 × 33.53 cm".
    static func pair(_ width: Double, _ height: Double) -> String { "\(string(width)) × \(string(height)) \(unitSuffix)" }

    /// Up to four decimal places, at least one: 23.5, 13.4, 0.0625.
    static func decimalString(_ value: Double) -> String {
        var text = String(format: "%.4f", value)
        while text.hasSuffix("0"), !text.hasSuffix(".0") { text.removeLast() }
        return text == "-0.0" ? "0.0" : text
    }

    /// A whole number and a reduced fraction to the nearest 16th: "23 1/8", "1/2", "-3", "0".
    static func fractionString(_ value: Double) -> String {
        let sixteenths = Int((abs(value) * Double(denominator)).rounded())
        let whole = sixteenths / denominator
        let remainder = sixteenths % denominator
        let sign = value < 0 && sixteenths != 0 ? "-" : ""
        guard remainder != 0 else { return "\(sign)\(whole)" }
        let divisor = gcd(remainder, denominator)
        let fraction = "\(remainder / divisor)/\(denominator / divisor)"
        return whole == 0 ? "\(sign)\(fraction)" : "\(sign)\(whole) \(fraction)"
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }

    // MARK: - Parsing

    /// Reads "23.5", "23 1/8", "23-1/8", "1/8", "-1 1/2", with an optional unit after it ("in", a quote mark,
    /// "cm" or "mm"). With no unit, the number is in the chosen unit. Returns inches, or nil when the
    /// text isn't a measurement.
    static func parse(_ text: String) -> Double? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var unitsPerInch = unit.unitsPerInch
        let suffixes: [(String, Double)] = [("inches", 1), ("inch", 1), ("in", 1), ("\"", 1), ("”", 1), ("″", 1),
                                            ("centimeters", 2.54), ("centimeter", 2.54), ("cm", 2.54),
                                            ("millimeters", 25.4), ("millimeter", 25.4), ("mm", 25.4)]
        for (suffix, perInch) in suffixes where t.hasSuffix(suffix) {
            t = String(t.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            unitsPerInch = perInch
            break
        }
        var negative = false
        if t.hasPrefix("-") { negative = true; t.removeFirst() } else if t.hasPrefix("+") { t.removeFirst() }

        let parts = t.split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
        let magnitude: Double?
        switch parts.count {
        case 1:
            magnitude = number(parts[0])
        case 2:
            // A whole number followed by a fraction, as in "23 1/8".
            if let whole = Double(parts[0]), whole >= 0, parts[1].contains("/"), let fraction = number(parts[1]) {
                magnitude = whole + fraction
            } else {
                magnitude = nil
            }
        default:
            magnitude = nil
        }
        guard let magnitude else { return nil }
        return (negative ? -magnitude : magnitude) / unitsPerInch
    }

    /// A decimal ("23.5") or a plain fraction ("1/8").
    private static func number(_ token: String) -> Double? {
        guard token.contains("/") else { return Double(token) }
        let pieces = token.split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.count == 2, let numerator = Double(pieces[0]), let denominator = Double(pieces[1]), denominator != 0 else { return nil }
        return numerator / denominator
    }
}
