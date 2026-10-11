//
//  MeasurementFormat.swift
//  ScreenBean
//
//  How measurements in inches are shown and typed: decimals ("23.125") or
//  fractions to the nearest 16th ("23 1/8"). Either form can always be typed.
//

import Foundation

enum MeasurementFormat {
    /// Posted when `useFractions` changes, so open fields can redraw.
    static let didChange = Notification.Name("ScreenBean.MeasurementFormatDidChange")

    /// Fractions are rounded to this denominator.
    static let denominator = 16

    private static let key = "ScreenBean.UseFractions"

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
        useFractions ? 1.0 / Double(denominator) : decimalStep
    }

    /// Rounds to the nearest 16th.
    static func roundedToFraction(_ value: Double) -> Double {
        (value * Double(denominator)).rounded() / Double(denominator)
    }

    // MARK: - Formatting

    static func string(_ value: Double) -> String {
        useFractions ? fractionString(value) : decimalString(value)
    }

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

    /// Reads "23.5", "23 1/8", "23-1/8", "1/8", "-1 1/2", with an optional trailing inch mark or "in".
    /// Returns nil when the text isn't a measurement.
    static func parse(_ text: String) -> Double? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for suffix in ["inches", "inch", "in", "\"", "”", "″"] where t.hasSuffix(suffix) {
            t = String(t.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
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
        return negative ? -magnitude : magnitude
    }

    /// A decimal ("23.5") or a plain fraction ("1/8").
    private static func number(_ token: String) -> Double? {
        guard token.contains("/") else { return Double(token) }
        let pieces = token.split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.count == 2, let numerator = Double(pieces[0]), let denominator = Double(pieces[1]), denominator != 0 else { return nil }
        return numerator / denominator
    }
}
