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
        
        let mainView = DisplayArrangementView()
        mainView.wantsLayer = true

        // Focused inspector for the currently selected display.
        let inspectorView = NSView()
        inspectorView.translatesAutoresizingMaskIntoConstraints = false
        inspectorView.wantsLayer = true
        inspectorView.layer?.backgroundColor =
            NSColor.controlBackgroundColor.cgColor

        let inspectorTitle = NSTextField(labelWithString: "Display Inspector")
        inspectorTitle.font = NSFont.boldSystemFont(ofSize: 16)

        let selectionName = NSTextField(labelWithString: "No display selected")
        selectionName.font = NSFont.boldSystemFont(ofSize: 13)
        selectionName.lineBreakMode = .byTruncatingTail

        let resolutionValue = NSTextField(labelWithString: "—")
        let physicalSizeValue = NSTextField(labelWithString: "—")
        let pixelDensityValue = NSTextField(labelWithString: "—")
        let displayRoleValue = NSTextField(labelWithString: "—")

        func makeInspectorRow(title: String, value: NSTextField) -> NSStackView {
            let titleLabel = NSTextField(labelWithString: title)
            titleLabel.textColor = .secondaryLabelColor
            titleLabel.font = NSFont.systemFont(ofSize: 11)

            let row = NSStackView(views: [titleLabel, value])
            row.orientation = .vertical
            row.alignment = .leading
            row.spacing = 3
            return row
        }

        let inspectorStack = NSStackView(views: [
            inspectorTitle,
            selectionName,
            makeInspectorRow(title: "Resolution", value: resolutionValue),
            makeInspectorRow(title: "Physical size", value: physicalSizeValue),
            makeInspectorRow(title: "Pixel density", value: pixelDensityValue),
            makeInspectorRow(title: "Display role", value: displayRoleValue)
        ])
        inspectorStack.orientation = .vertical
        inspectorStack.alignment = .leading
        inspectorStack.spacing = 16
        inspectorStack.translatesAutoresizingMaskIntoConstraints = false

        inspectorView.addSubview(inspectorStack)

        NSLayoutConstraint.activate([
            inspectorStack.leadingAnchor.constraint(
                equalTo: inspectorView.leadingAnchor,
                constant: 16
            ),
            inspectorStack.trailingAnchor.constraint(
                equalTo: inspectorView.trailingAnchor,
                constant: -16
            ),
            inspectorStack.topAnchor.constraint(
                equalTo: inspectorView.topAnchor,
                constant: 20
            )
        ])

        mainView.onSelectionChanged = { display in
            guard let display else {
                selectionName.stringValue = "No display selected"
                resolutionValue.stringValue = "—"
                physicalSizeValue.stringValue = "—"
                pixelDensityValue.stringValue = "—"
                displayRoleValue.stringValue = "—"
                return
            }

            selectionName.stringValue = display.nickname
            resolutionValue.stringValue =
                "\(display.pixelWidth) × \(display.pixelHeight) pixels"
            physicalSizeValue.stringValue = String(
                format: "%.1f × %.1f inches",
                display.physicalWidthInches,
                display.physicalHeightInches
            )
            pixelDensityValue.stringValue = String(
                format: "%.0f PPI",
                display.ppi
            )
            displayRoleValue.stringValue =
                display.isPrimary ? "Primary display" : "Secondary display"
        }

        let centerButton = NSButton(
            title: "Center View",
            target: mainView,
            action: #selector(DisplayArrangementView.centerView)
        )

        let fitButton = NSButton(
            title: "Zoom to Fit",
            target: mainView,
            action: #selector(DisplayArrangementView.zoomToFitFromButton)
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
        container.addSubview(inspectorView)
        container.addSubview(buttonStack)

        mainView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            mainView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            mainView.trailingAnchor.constraint(equalTo: inspectorView.leadingAnchor),
            mainView.topAnchor.constraint(equalTo: container.topAnchor),
            mainView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            inspectorView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            inspectorView.topAnchor.constraint(equalTo: container.topAnchor),
            inspectorView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            inspectorView.widthAnchor.constraint(equalToConstant: 260),

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
