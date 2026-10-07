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
        
        let buttonStack = NSStackView(
            views: [
                centerButton,
                fitButton
            ]
        )
        
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
                
        mainView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        
        mainView.displays = DisplayInfo.detectDisplays()
        mainView.setNeedsDisplay(mainView.bounds)

        mainView.needsDisplay = true // force redraw

let container = NSView()
container.translatesAutoresizingMaskIntoConstraints = false

container.addSubview(mainView)
container.addSubview(buttonStack)

mainView.translatesAutoresizingMaskIntoConstraints = false

NSLayoutConstraint.activate([
    mainView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
    mainView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    mainView.topAnchor.constraint(equalTo: container.topAnchor),
    mainView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

    buttonStack.leadingAnchor.constraint(
        equalTo: container.leadingAnchor,
        constant: 12
    ),

    buttonStack.bottomAnchor.constraint(
        equalTo: container.bottomAnchor,
        constant: -12
    )
])


        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ScreenBean"
        window.contentView = container
        window.minSize = NSSize(width: 400, height: 300)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.contentView?.wantsLayer = true
        NSApp.activate(ignoringOtherApps: true)

    }
    
}
