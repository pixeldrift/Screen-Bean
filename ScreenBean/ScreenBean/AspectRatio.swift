//
//  AspectRatio.swift
//  ScreenBean
//
//  Aspect ratios as people write them: "16:9", "16/9", "16x9" or a plain "1.78".
//

import Foundation

enum AspectRatio {
    /// Ratios worth showing by name, wide side first.
    private static let named: [(Int, Int)] = [(16, 9), (16, 10), (4, 3), (3, 2), (5, 4), (21, 9), (32, 9), (32, 10), (2, 1), (1, 1)]

    /// "16:9" for a familiar shape, otherwise "1.43:1". Portrait shapes read tall side first, e.g. "9:16".
    static func string(_ ratio: Double) -> String {
        guard ratio > 0, ratio.isFinite else { return "—" }
        let wide = max(ratio, 1 / ratio)
        let portrait = ratio < 1
        for (a, b) in named where abs(wide - Double(a) / Double(b)) < 0.01 {
            return portrait ? "\(b):\(a)" : "\(a):\(b)"
        }
        let text = String(format: "%.2f:1", ratio)
        return text
    }

    /// Width divided by height from text like "16:9", "16/9", "16 x 9" or "1.78". Nil if it isn't one.
    static func parse(_ text: String) -> Double? {
        let cleaned = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [":", "/", "x", "×"] where cleaned.contains(separator) {
            let parts = cleaned.components(separatedBy: separator).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), a > 0, b > 0 else { return nil }
            return a / b
        }
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }
}
