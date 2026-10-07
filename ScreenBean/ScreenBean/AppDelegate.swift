//
//  AppDelegate.swift
//  ScreenBean
//  Your display settings caffeinated!
//
//  Created by Nathan Pizar on 5/21/25.

import Cocoa
import CoreGraphics

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        
        print("Launching ScreenBean")
        
        // App Menu Bar
        
        let mainMenu = NSMenu()

        // Begin App (ScreenBean) menu
        
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        let quitTitle = "Quit ScreenBean"
        let quitItem = NSMenuItem(title: quitTitle, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu

        NSApp.mainMenu = mainMenu
        
        // -- End App Menu Bar
        
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        let centerButton = NSButton(
            title: "Center View",
            target: mainView,
            action: #selector(DisplayArrangementView.centerView)
        )

        let fitButton = NSButton(
            title: "Scale to Fit",
            target: mainView,
            action: #selector(DisplayArrangementView.scaleToFit)
        )

        centerButton.bezelStyle = .rounded
        fitButton.bezelStyle = .rounded
        
        mainView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        
        mainView.displays = DisplayInfo.detectDisplays()
        mainView.setNeedsDisplay(mainView.bounds)

        mainView.needsDisplay = true // force redraw

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ScreenBean"
        window.contentView = mainView
        window.minSize = NSSize(width: 400, height: 300)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.contentView?.wantsLayer = true
        NSApp.activate(ignoringOtherApps: true)

    }
    
}
