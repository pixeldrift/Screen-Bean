//
//  MouseTransitEngine.swift
//  ScreenBean
//
//  Makes the real pointer follow the transit zones. An event tap watches pointer movement and,
//  when a move leaves a display through a zone, puts the pointer where the zone says instead
//  (see `TransitMapper`). The tap needs Accessibility permission, and can't run in the app sandbox.
//  It runs on its own thread so a busy window can't make the pointer lag.
//

import Cocoa
import ApplicationServices

/// Whether mouse mapping is switched on, kept between launches.
enum MouseMappingSettings {
    private static let key = "ScreenBean.MouseMappingEnabled"
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

final class MouseTransitEngine {
    static let shared = MouseTransitEngine()

    /// Guards the tables and the tap's handles, which the main thread and the tap thread both touch.
    private let lock = NSLock()
    private var mapper = TransitMapper()
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    /// Where the pointer was after the last event. Only the tap's thread reads or writes it.
    private var lastLocation: CGPoint?

    private init() {}

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return tap != nil
    }

    /// Whether the app has been allowed to control the computer in System Settings ▸ Privacy & Security ▸ Accessibility.
    static var hasAccess: Bool { AXIsProcessTrusted() }

    /// Asks macOS to show its permission prompt, which points the user at Accessibility settings.
    static func requestAccess() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Gives the tap new zones and displays. Safe to call at any time.
    func update(_ newMapper: TransitMapper) {
        lock.lock()
        mapper = newMapper
        lock.unlock()
    }

    /// Starts watching the pointer. Returns false if macOS refused, which means no Accessibility permission.
    @discardableResult
    func start() -> Bool {
        lock.lock()
        if tap != nil { lock.unlock(); return true }
        lock.unlock()
        guard Self.hasAccess else { return false }

        let moves: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let mask = moves.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            return Unmanaged<MouseTransitEngine>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
        }
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        lock.lock()
        tap = newTap
        lock.unlock()
        // After a warp macOS ignores the mouse for a moment by default, which would make a crossing stutter.
        _ = CGSetLocalEventsSuppressionInterval(0)

        let thread = Thread { [weak self] in
            guard let self else { return }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
            let current = CFRunLoopGetCurrent()
            self.lock.lock(); self.runLoop = current; self.lock.unlock()
            CFRunLoopAddSource(current, source, .commonModes)
            CGEvent.tapEnable(tap: newTap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "ScreenBean Mouse Transit"
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }

    func stop() {
        lock.lock()
        let oldTap = tap, oldLoop = runLoop
        tap = nil
        runLoop = nil
        lock.unlock()
        if let oldTap {
            CGEvent.tapEnable(tap: oldTap, enable: false)
            CFMachPortInvalidate(oldTap)
        }
        if let oldLoop { CFRunLoopStop(oldLoop) }
    }

    // MARK: - The tap

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)
        // macOS switches a tap off if it is slow or if input is being protected; switch it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock(); let current = tap; lock.unlock()
            if let current { CGEvent.tapEnable(tap: current, enable: true) }
            lastLocation = nil
            return passThrough
        }
        // Whatever happens below, the next move starts from where this one ended up.
        defer { lastLocation = event.location }
        guard let previous = lastLocation else { return passThrough }

        let proposed = CGPoint(
            x: previous.x + event.getDoubleValueField(.mouseEventDeltaX),
            y: previous.y + event.getDoubleValueField(.mouseEventDeltaY)
        )
        lock.lock(); let table = mapper; lock.unlock()
        if let landing = table.crossing(from: previous, to: proposed) {
            event.location = landing
            CGWarpMouseCursorPosition(landing)
        }
        return passThrough
    }
}
