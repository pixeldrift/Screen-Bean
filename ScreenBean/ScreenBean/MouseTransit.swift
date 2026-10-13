//
//  MouseTransit.swift
//  ScreenBean
//
//  Where the mouse can cross from one display to another. A transit zone links a stretch of one
//  display's outline to a stretch of another's: the ends of the two stretches correspond, and
//  everything between them is matched proportionally. Zones are found automatically between
//  displays that face each other (like the gap guides) and can then be reshaped by moving their
//  ends. Only the table and its drawing live here; nothing moves the real mouse yet.
//

import Cocoa

/// A display's outline as a loop, measured from 0 to 4: the top edge from left to right is 0...1, the right edge
/// from top to bottom 1...2, the bottom edge from right to left 2...3, and the left edge from bottom to top 3...4.
/// 4 is the same corner as 0. Positions are in workspace inches with y pointing up.
enum Perimeter {
    /// The point on `rect`'s outline at `u`. Values outside 0..<4 wrap around.
    static func point(_ u: Double, in rect: CGRect) -> CGPoint {
        var n = u.truncatingRemainder(dividingBy: 4)
        if n < 0 { n += 4 }
        let edge = Int(n.rounded(.down))
        let f = CGFloat(n - Double(edge))
        switch edge {
        case 0: return CGPoint(x: rect.minX + f * rect.width, y: rect.maxY)
        case 1: return CGPoint(x: rect.maxX, y: rect.maxY - f * rect.height)
        case 2: return CGPoint(x: rect.maxX - f * rect.width, y: rect.minY)
        default: return CGPoint(x: rect.minX, y: rect.minY + f * rect.height)
        }
    }

    /// Which edge `u` is on: 0 top, 1 right, 2 bottom, 3 left. A corner counts as the edge that starts there.
    static func edge(_ u: Double) -> Int {
        var n = u.truncatingRemainder(dividingBy: 4)
        if n < 0 { n += 4 }
        return Int(n.rounded(.down)) % 4
    }

    /// The position on the outline nearest to `p`, from 0 to just under 4.
    static func parameter(for p: CGPoint, in rect: CGRect) -> Double {
        let width = max(rect.width, 0.0001), height = max(rect.height, 0.0001)
        // Where along each edge the nearest point is, as a fraction of that edge.
        let fractions: [CGFloat] = [
            (p.x - rect.minX) / width,
            (rect.maxY - p.y) / height,
            (rect.maxX - p.x) / width,
            (p.y - rect.minY) / height
        ]
        var bestU = 0.0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for edge in 0..<4 {
            let fraction = min(max(fractions[edge], 0), 1)
            let u = Double(edge) + Double(fraction)
            let nearest = point(u, in: rect)
            let distance = hypot(nearest.x - p.x, nearest.y - p.y)
            if distance < bestDistance {
                bestDistance = distance
                bestU = u
            }
        }
        return bestU >= 4 ? 0 : bestU
    }

    /// The position on the same side of the outline as `u` (a left or right edge, where height changes along it) that is
    /// level with `target`, or nil if the dot is on a top or bottom edge or the level spot is off the edge.
    static func levelPosition(_ u: Double, in rect: CGRect, with target: CGPoint) -> Double? {
        let height = Double(rect.height)
        guard height > 0 else { return nil }
        let start = u.rounded(.down)
        switch edge(u) {
        case 1:
            let f = Double(rect.maxY - target.y) / height
            return f >= 0 && f <= 1 ? start + f : nil
        case 3:
            let f = Double(target.y - rect.minY) / height
            return f >= 0 && f <= 1 ? start + f : nil
        default:
            return nil
        }
    }

    /// The shortest signed way from `a` to `b` around the loop, in -2...2.
    static func delta(from a: Double, to b: Double) -> Double {
        var d = (b - a).truncatingRemainder(dividingBy: 4)
        if d > 2 { d -= 4 } else if d <= -2 { d += 4 }
        return d
    }

    /// The walk from `a` to `b` along the line of positions (no wrapping), with every corner passed on the way.
    static func arc(from a: Double, to b: Double) -> [Double] {
        var path = [a]
        if b > a {
            var k = a.rounded(.down) + 1
            while k < b - 1e-9 { path.append(k); k += 1 }
        } else if b < a {
            var k = a.rounded(.up) - 1
            while k > b + 1e-9 { path.append(k); k -= 1 }
        }
        if b != a { path.append(b) }
        return path
    }
}

/// One display's end of a zone: a stretch of its outline from `u0` to `u1` (see `Perimeter`). The stretch is the walk
/// from `u0` to `u1` along the line of positions, so it can run around a corner, or past the 0/4 corner by going
/// beyond 4. `u0` pairs with the other side's `u0`, and `u1` with its `u1`.
struct TransitSide: Codable, Equatable {
    var displayKey: String
    var u0: Double
    var u1: Double

    var middle: Double { (u0 + u1) / 2 }

    /// Positions are kept so the lower one is within 0..<4; the stretch itself isn't changed.
    mutating func normalize() {
        let shift = -((min(u0, u1)) / 4).rounded(.down) * 4
        u0 += shift
        u1 += shift
    }
}

struct TransitZone: Codable, Equatable {
    /// Names the pair of displays and which way they face, so edits to an automatic zone are remembered.
    var id: String
    var a: TransitSide
    var b: TransitSide
    /// A zone the user has taken away. Kept so it isn't found again.
    var isRemoved = false
}

/// One stretch of a real screen's edge that a zone covers, for drawing on that screen: where it is on the outline, the
/// color of the display it connects to, and that display's letter.
struct ScreenTransitMark {
    let u0: Double
    let u1: Double
    let color: NSColor
    let partnerLabel: String
}

// MARK: - Finding zones

enum TransitDetector {
    struct Panel {
        let key: String
        let rect: CGRect
    }

    /// A zone between every pair of displays that face each other across a gap or a shared edge, linking the whole
    /// of the two facing edges: top-left to top-left and bottom-right to bottom-right, and so on. `isBlocked` can rule
    /// out a pair when another display sits between them.
    static func autoZones(for panels: [Panel], isBlocked: (CGRect, String, String) -> Bool = { _, _, _ in false }) -> [TransitZone] {
        var zones: [TransitZone] = []
        for i in panels.indices {
            for j in panels.indices where j > i {
                let a = panels[i], b = panels[j]
                let lowY = max(a.rect.minY, b.rect.minY), highY = min(a.rect.maxY, b.rect.maxY)
                if highY - lowY > 0.01 {
                    // Side by side: they overlap in y.
                    let pair: (left: Panel, right: Panel)?
                    if a.rect.maxX <= b.rect.minX + 0.001 { pair = (a, b) } else if b.rect.maxX <= a.rect.minX + 0.001 { pair = (b, a) } else { pair = nil }
                    if let pair {
                        let between = CGRect(x: pair.left.rect.maxX, y: lowY, width: max(pair.right.rect.minX - pair.left.rect.maxX, 0), height: highY - lowY)
                        if !isBlocked(between, a.key, b.key) {
                            zones.append(TransitZone(
                                id: "h:\(pair.left.key)>\(pair.right.key)",
                                a: TransitSide(displayKey: pair.left.key, u0: 1, u1: 2),
                                b: TransitSide(displayKey: pair.right.key, u0: 4, u1: 3)
                            ))
                        }
                    }
                    continue
                }
                let lowX = max(a.rect.minX, b.rect.minX), highX = min(a.rect.maxX, b.rect.maxX)
                guard highX - lowX > 0.01 else { continue }
                // Stacked: they overlap in x.
                let pair: (upper: Panel, lower: Panel)?
                if a.rect.maxY <= b.rect.minY + 0.001 { pair = (b, a) } else if b.rect.maxY <= a.rect.minY + 0.001 { pair = (a, b) } else { pair = nil }
                if let pair {
                    let between = CGRect(x: lowX, y: pair.lower.rect.maxY, width: highX - lowX, height: max(pair.upper.rect.minY - pair.lower.rect.maxY, 0))
                    if !isBlocked(between, a.key, b.key) {
                        zones.append(TransitZone(
                            id: "v:\(pair.upper.key)>\(pair.lower.key)",
                            a: TransitSide(displayKey: pair.upper.key, u0: 3, u1: 2),
                            b: TransitSide(displayKey: pair.lower.key, u0: 0, u1: 1)
                        ))
                    }
                }
            }
        }
        return zones
    }
}

// MARK: - Edits

/// The zones the user has changed or removed, by zone id, saved between launches. Zones nobody has touched are
/// found again automatically, so only these are kept.
final class TransitStore {
    static let shared = TransitStore()
    static let didChange = Notification.Name("ScreenBean.TransitDidChange")
    private let key = "ScreenBean.TransitOverrides"

    private(set) var overrides: [TransitZone]

    private init() {
        if let data = UserDefaults.standard.data(forKey: key), let saved = try? JSONDecoder().decode([TransitZone].self, from: data) {
            overrides = saved
        } else {
            overrides = []
        }
    }

    func replaceAll(_ zones: [TransitZone]) {
        overrides = zones
        save()
    }

    func set(_ zone: TransitZone) {
        if let index = overrides.firstIndex(where: { $0.id == zone.id }) { overrides[index] = zone } else { overrides.append(zone) }
        save()
    }

    /// The automatic zones with the user's changes applied and removed ones left out.
    func resolved(_ automatic: [TransitZone]) -> [TransitZone] {
        automatic.compactMap { zone in
            let current = overrides.first(where: { $0.id == zone.id }) ?? zone
            return current.isRemoved ? nil : current
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(overrides) { UserDefaults.standard.set(data, forKey: key) }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}
