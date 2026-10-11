//
//  AppDelegate.swift
//  ScreenBean
//  Your display settings caffeinated!
//

import Cocoa
import CoreGraphics

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit ScreenBean", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let mainView = DisplayArrangementView()
        mainView.wantsLayer = true
        mainView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let sidebar = SidebarView()
        let inspector = sidebar.inspector
        let store = ImageLayerStore.shared
        let layerPanels: [(slot: ImageLayerSlot, panel: ImageLayerPanel)] = [
            (.referenceImage, sidebar.referenceImagePanel), (.wallpaper, sidebar.wallpaperPanel)
        ]
        func setLayer(_ slot: ImageLayerSlot, _ change: (inout DisplayArrangementView.ImageLayer) -> Void) {
            switch slot {
            case .referenceImage: change(&mainView.referenceLayer)
            case .wallpaper: change(&mainView.wallpaperLayer)
            }
        }
        for (slot, panel) in layerPanels {
            let image = store.loadImage(slot), blend = store.loadBlend(slot)
            panel.restore(image: image, blend: blend)
            setLayer(slot) { $0.image = image; $0.blend = ImageLayerBlend(value: blend) }
            panel.onImageChanged = { image, data in
                store.saveImageData(data, for: slot)
                setLayer(slot) { $0.image = image }
            }
            panel.onBlendChanged = { value in
                store.saveBlend(value, for: slot)
                setLayer(slot) { $0.blend = ImageLayerBlend(value: value) }
            }
        }
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        inspector.onChange = { [weak mainView] edit in mainView?.updateSelectedDisplay(edit) }
        mainView.onSelectionChanged = { [weak mainView, weak sidebar] display in
            sidebar?.setDisplaySelected(display != nil)
            let position = mainView?.selectedPosition()
            sidebar?.inspector.refresh(display, x: position?.x ?? 0, y: position?.y ?? 0)
        }
        mainView.onDisplayValuesChanged = { [weak inspector] display, x, y in
            inspector?.refresh(display, x: x, y: y)
        }

        let centerButton = NSButton(title: "Center View", target: mainView, action: #selector(DisplayArrangementView.centerView))
        let fitButton = NSButton(title: "Zoom to Fit", target: mainView, action: #selector(DisplayArrangementView.zoomToFitFromButton))
        centerButton.bezelStyle = .rounded
        fitButton.bezelStyle = .rounded
        let buttonStack = NSStackView(views: [centerButton, fitButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        mainView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(mainView)
        container.addSubview(sidebar)
        container.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            mainView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            mainView.trailingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            mainView.topAnchor.constraint(equalTo: container.topAnchor),
            mainView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            sidebar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sidebar.topAnchor.constraint(equalTo: container.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 300),
            buttonStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            buttonStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])

        mainView.displays = DisplayInfo.detectDisplays()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 680), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "ScreenBean"
        window.contentView = container
        window.minSize = NSSize(width: 600, height: 400)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
