//
//  TransitMapper.swift
//  ScreenBean
//
//  The rule for crossing between displays. Given where the pointer was and where it is about to
//  be, it says where the pointer should land instead when the move leaves a display through a
//  transit zone, matching the crossing point proportionally along the other display's edge. It
//  knows nothing about events or the system, so it can be tested on its own.
//
//  Positions are in global pointer coordinates: points, origin at the top left of the main
//  display, y pointing down.
//

import CoreGraphics
import Foundation

struct TransitMapper {
    struct Screen {
        let key: String
        /// The display's bounds in global pointer coordinates.
        let bounds: CGRect
        /// The screen's physical size in inches, which sets how far along an edge a crossing is.
        let size: CGSize
    }

    var screens: [Screen] = []
    var zones: [TransitZone] = []
    /// When on, a move that leaves a display anywhere no zone covers stops at the edge instead of following macOS's own
    /// arrangement. With no zones at all there is nothing to enforce, so moves are left alone.
    var blocksOutsideZones = true

    // MARK: - Crossing

    /// Where the pointer should go for a move from `from` to `to`, or nil to leave the move alone (it stays on one
    /// display). A move that leaves through a zone lands on the other display; one that leaves anywhere else is held at
    /// the edge.
    func crossing(from: CGPoint, to: CGPoint) -> CGPoint? {
        guard let source = screens.first(where: { Self.contains(Self.limit($0), from) }) else { return nil }
        let box = Self.limit(source)
        guard !Self.contains(box, to), let exit = Self.exit(from: from, to: to, box: box) else { return nil }

        // Where along the source display's outline the pointer leaves, in the units of `Perimeter`.
        let u = Self.position(of: exit.point, edge: exit.edge, in: box)
        for zone in zones {
            for (mine, theirs) in [(zone.a, zone.b), (zone.b, zone.a)] where mine.displayKey == source.key {
                guard let target = screens.first(where: { $0.key == theirs.displayKey }), target.key != source.key else { continue }
                // The stretch may run past the 0 / 4 corner, so the position can be 4 further round.
                let low = min(mine.u0, mine.u1) - 1e-6, high = max(mine.u0, mine.u1) + 1e-6
                guard let along = [u - 4, u, u + 4, u + 8].first(where: { $0 >= low && $0 <= high }) else { continue }

                // How far along the source stretch (by physical length), and the same distance along the target's.
                let start = Self.distance(at: mine.u0, size: source.size), end = Self.distance(at: mine.u1, size: source.size)
                guard abs(end - start) > 1e-9 else { continue }
                let fraction = min(max((Self.distance(at: along, size: source.size) - start) / (end - start), 0), 1)
                let there = Self.distance(at: theirs.u0, size: target.size) + fraction * (Self.distance(at: theirs.u1, size: target.size) - Self.distance(at: theirs.u0, size: target.size))
                let arrival = Self.position(atDistance: there, size: target.size)
                return Self.landing(at: arrival, in: Self.limit(target), overshoot: exit.overshoot)
            }
        }
        // Not through any zone: the pointer can't cross here, so it stays on this display, sliding along the edge.
        guard blocksOutsideZones, !zones.isEmpty else { return nil }
        return CGPoint(x: min(max(to.x, box.minX), box.maxX), y: min(max(to.y, box.minY), box.maxY))
    }

    // MARK: - Geometry

    /// The pointer can sit on the pixels from the left and top edge to one short of the right and bottom.
    static func limit(_ screen: Screen) -> CGRect {
        CGRect(x: screen.bounds.minX, y: screen.bounds.minY, width: max(screen.bounds.width - 1, 1), height: max(screen.bounds.height - 1, 1))
    }

    private static func contains(_ box: CGRect, _ p: CGPoint) -> Bool {
        p.x >= box.minX && p.x <= box.maxX && p.y >= box.minY && p.y <= box.maxY
    }

    /// Where a move that starts inside `box` and ends outside it crosses the box's edge: the point, which edge
    /// (0 top, 1 right, 2 bottom, 3 left), and how far past the edge the move would have gone.
    private static func exit(from a: CGPoint, to b: CGPoint, box: CGRect) -> (point: CGPoint, edge: Int, overshoot: CGFloat)? {
        let dx = b.x - a.x, dy = b.y - a.y
        var best: (t: CGFloat, point: CGPoint, edge: Int, overshoot: CGFloat)?
        func consider(_ t: CGFloat, edge: Int, overshoot: CGFloat) {
            guard t >= 0, t <= 1 else { return }
            let point = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
            // The crossing has to be on the edge itself, not beyond its end.
            let onEdge = edge % 2 == 0 ? (point.x >= box.minX - 1e-6 && point.x <= box.maxX + 1e-6) : (point.y >= box.minY - 1e-6 && point.y <= box.maxY + 1e-6)
            if onEdge, best == nil || t < best!.t { best = (t, point, edge, overshoot) }
        }
        if dx > 0 { consider((box.maxX - a.x) / dx, edge: 1, overshoot: b.x - box.maxX) }
        if dx < 0 { consider((box.minX - a.x) / dx, edge: 3, overshoot: box.minX - b.x) }
        if dy > 0 { consider((box.maxY - a.y) / dy, edge: 2, overshoot: b.y - box.maxY) }
        if dy < 0 { consider((box.minY - a.y) / dy, edge: 0, overshoot: box.minY - b.y) }
        return best.map { ($0.point, $0.edge, max($0.overshoot, 0)) }
    }

    /// The position on a display's outline (see `Perimeter`) of a point on one of its edges.
    private static func position(of p: CGPoint, edge: Int, in box: CGRect) -> Double {
        switch edge {
        case 0: return Double((p.x - box.minX) / box.width)
        case 1: return 1 + Double((p.y - box.minY) / box.height)
        case 2: return 2 + Double((box.maxX - p.x) / box.width)
        default: return 3 + Double((box.maxY - p.y) / box.height)
        }
    }

    /// How far along the outline, in inches from the top-left corner going clockwise, a position is. A position past
    /// the 0 / 4 corner counts a full loop more.
    static func distance(at u: Double, size: CGSize) -> Double {
        let lengths = [Double(size.width), Double(size.height), Double(size.width), Double(size.height)]
        let loop = lengths.reduce(0, +)
        let loops = (u / 4).rounded(.down)
        var remaining = u - loops * 4
        var total = loops * loop
        for length in lengths {
            let step = min(max(remaining, 0), 1)
            total += step * length
            remaining -= 1
        }
        return total
    }

    /// The position on the outline that is `d` inches along it. The reverse of `distance(at:size:)`.
    static func position(atDistance d: Double, size: CGSize) -> Double {
        let lengths = [Double(size.width), Double(size.height), Double(size.width), Double(size.height)]
        let loop = lengths.reduce(0, +)
        guard loop > 0 else { return 0 }
        let loops = (d / loop).rounded(.down)
        var remaining = d - loops * loop
        var u = loops * 4
        for (index, length) in lengths.enumerated() {
            if remaining <= length || index == 3 {
                return u + (length > 0 ? min(remaining / length, 1) : 0)
            }
            remaining -= length
            u += 1
        }
        return u
    }

    /// The pixel to put the pointer on for a position on a display's outline, nudged inward by the part of the move
    /// that went past the edge.
    private static func landing(at u: Double, in box: CGRect, overshoot: CGFloat) -> CGPoint {
        var n = u.truncatingRemainder(dividingBy: 4)
        if n < 0 { n += 4 }
        let edge = Int(n.rounded(.down)) % 4
        let f = CGFloat(n - n.rounded(.down))
        let point: CGPoint
        switch edge {
        case 0: point = CGPoint(x: box.minX + f * box.width, y: box.minY)
        case 1: point = CGPoint(x: box.maxX, y: box.minY + f * box.height)
        case 2: point = CGPoint(x: box.maxX - f * box.width, y: box.maxY)
        default: point = CGPoint(x: box.minX, y: box.maxY - f * box.height)
        }
        // Inward is away from the edge; at a corner it is away from both.
        func inward(_ edge: Int) -> CGPoint {
            switch edge % 4 {
            case 0: return CGPoint(x: 0, y: 1)
            case 1: return CGPoint(x: -1, y: 0)
            case 2: return CGPoint(x: 0, y: -1)
            default: return CGPoint(x: 1, y: 0)
            }
        }
        var push = inward(edge)
        if f < 1e-9 {
            let other = inward(edge + 3)
            push = CGPoint(x: push.x + other.x, y: push.y + other.y)
        }
        let length = max(hypot(push.x, push.y), 1e-9)
        let step = max(overshoot, 2)
        let moved = CGPoint(x: point.x + push.x / length * step, y: point.y + push.y / length * step)
        return CGPoint(x: min(max(moved.x, box.minX), box.maxX), y: min(max(moved.y, box.minY), box.maxY))
    }
}
