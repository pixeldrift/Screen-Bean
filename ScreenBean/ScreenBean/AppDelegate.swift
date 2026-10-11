//
//  AppDelegate.swift
//  ScreenBean
//  Your display settings caffeinated!
//

import Cocoa
import CoreGraphics

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    private var mainView: DisplayArrangementView?
    private let overlays = DisplayOverlayManager()
    private var sidebarView: SidebarView!
    private var identifyButton: NSButton { sidebarView.settingsPanel.identifyButton }
    private var previewButton: NSButton { sidebarView.previewWallpaperButton }
    private var liveCheckbox: NSButton { sidebarView.liveCheckbox }
    private var liveWork: DispatchWorkItem?
    private let switchPresetMenu = NSMenu(title: "Switch Layout")
    private let renamePresetMenu = NSMenu(title: "Rename Layout")
    private let deletePresetMenu = NSMenu(title: "Delete Layout")
    private var screenChangeWork: DispatchWorkItem?
    private var excludePrimaryCheckbox: NSButton { sidebarView.settingsPanel.excludePrimaryCheckbox }
    private static let excludePrimaryKey = "ScreenBean.ExcludePrimaryFromIdentify"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit ScreenBean", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        for name in [GuideSettings.didChange, GuideStore.didChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refreshOverlays() }
        }
        // Edit: undo and redo for layout changes, plus the usual text editing commands.
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        let undoItem = NSMenuItem(title: "Undo", action: #selector(undoAction), keyEquivalent: "z")
        undoItem.target = self
        let redoItem = NSMenuItem(title: "Redo", action: #selector(redoAction), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        redoItem.target = self
        editMenu.addItem(undoItem)
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        // Layout: planned displays, and later saved layouts.
        let layoutMenuItem = NSMenuItem()
        mainMenu.addItem(layoutMenuItem)
        let layoutMenu = NSMenu(title: "Layout")
        let addVirtualItem = NSMenuItem(title: "Add Virtual Display…", action: #selector(addVirtualDisplay), keyEquivalent: "n")
        addVirtualItem.keyEquivalentModifierMask = [.command, .shift]
        addVirtualItem.target = self
        layoutMenu.addItem(addVirtualItem)
        let deleteVirtualItem = NSMenuItem(title: "Delete Virtual Display", action: #selector(deleteVirtualDisplay), keyEquivalent: "")
        deleteVirtualItem.target = self
        layoutMenu.addItem(deleteVirtualItem)
        layoutMenu.addItem(.separator())
        let savePresetItem = NSMenuItem(title: "Save Layout as Preset…", action: #selector(savePreset), keyEquivalent: "")
        savePresetItem.target = self
        layoutMenu.addItem(savePresetItem)
        let updatePresetItem = NSMenuItem(title: "Update Active Preset", action: #selector(updateActivePreset), keyEquivalent: "")
        updatePresetItem.target = self
        layoutMenu.addItem(updatePresetItem)
        for (title, submenu) in [("Switch to Preset", switchPresetMenu), ("Rename Preset", renamePresetMenu), ("Delete Preset", deletePresetMenu)] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            layoutMenu.addItem(item)
        }
        rebuildPresetMenus()
        NotificationCenter.default.addObserver(forName: LayoutPresetStore.didChange, object: nil, queue: .main) { [weak self] _ in self?.rebuildPresetMenus() }
        // Plugging or unplugging a display re-reads the layout and may suggest a saved preset for the new set.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.screenParametersChanged() }
        layoutMenuItem.submenu = layoutMenu
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        let fractionsItem = NSMenuItem(title: "Show Measurements as Fractions", action: #selector(toggleFractions), keyEquivalent: "")
        fractionsItem.target = self
        viewMenu.addItem(fractionsItem)
        let guidesItem = NSMenuItem(title: "Show Guides", action: #selector(toggleGuides), keyEquivalent: ";")
        guidesItem.target = self
        viewMenu.addItem(guidesItem)
        let gapItem = NSMenuItem(title: "Show Gap Measurements", action: #selector(toggleGapMeasurements), keyEquivalent: "")
        gapItem.target = self
        viewMenu.addItem(gapItem)
        let clearGuidesItem = NSMenuItem(title: "Clear Custom Guides", action: #selector(clearGuides), keyEquivalent: "")
        clearGuidesItem.target = self
        viewMenu.addItem(clearGuidesItem)
        viewMenuItem.submenu = viewMenu
        NSApp.mainMenu = mainMenu
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let mainView = DisplayArrangementView()
        mainView.wantsLayer = true
        mainView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        // Displays first, so new image frames can start centered on the arrangement.
        mainView.displays = DisplayInfo.detectDisplays()
        UndoCenter.shared.capture = { [weak mainView] in mainView?.captureSnapshot() }
        UndoCenter.shared.restore = { [weak mainView] in mainView?.restoreSnapshot($0) }
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
        mainView.onImageFrameChanged = { [weak sidebar] slot, frame in
            store.saveFrame(frame, for: slot)
            (slot == .referenceImage ? sidebar?.referenceImagePanel : sidebar?.wallpaperPanel)?.showFrame(frame)
            self.scheduleLivePreview()
        }
        mainView.onImageLockChanged = { [weak sidebar] slot, locked in
            store.saveLocked(locked, for: slot)
            (slot == .referenceImage ? sidebar?.referenceImagePanel : sidebar?.wallpaperPanel)?.setLocked(locked)
        }
        mainView.wallpaperClipsToDisplays = store.loadWallpaperClip()
        sidebar.wallpaperPanel.restoreClip(store.loadWallpaperClip())
        sidebar.wallpaperPanel.onClipChanged = { [weak mainView] clipped in
            store.saveWallpaperClip(clipped)
            mainView?.wallpaperClipsToDisplays = clipped
        }
        for (slot, panel) in layerPanels {
            let image = store.loadImage(slot), blend = store.loadBlend(slot)
            panel.restore(image: image, blend: blend)
            let locked = store.loadLocked(slot)
            panel.setLocked(locked)
            setLayer(slot) { $0.image = image; $0.blend = ImageLayerBlend(value: blend); $0.frame = store.loadFrame(slot); $0.isLocked = locked }
            panel.onLockChanged = { locked in
                UndoCenter.shared.perform(locked ? "Lock Image" : "Unlock Image") {
                    store.saveLocked(locked, for: slot)
                    setLayer(slot) { $0.isLocked = locked }
                }
            }
            panel.onFitRequested = { [weak mainView] in mainView?.fitImageToScreens(slot) }
            panel.onFrameChanged = { frame in
                UndoCenter.shared.perform("Edit Image", coalesceKey: "image-\(slot.rawValue)") {
                    setLayer(slot) { $0.frame = frame }
                    store.saveFrame(frame, for: slot)
                }
            }
            panel.onImageChanged = { image, data in
                store.saveImageData(data, for: slot)
                setLayer(slot) { $0.image = image }
                self.scheduleLivePreview()
                // A removed image shouldn't leave its lock behind for the next one.
                if image == nil {
                    store.saveLocked(false, for: slot)
                    panel.setLocked(false)
                    setLayer(slot) { $0.isLocked = false }
                }
            }
            panel.onBlendChanged = { value in
                store.saveBlend(value, for: slot)
                setLayer(slot) { $0.blend = ImageLayerBlend(value: value) }
            }
        }
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        inspector.onChange = { [weak mainView] edit in mainView?.updateSelectedDisplay(edit) }
        inspector.onAssignVirtual = { [weak mainView] id in mainView?.assignSelectedVirtualDisplay(to: id) }
        inspector.onDeleteVirtual = { [weak mainView] in mainView?.deleteSelectedVirtualDisplays() }
        mainView.onSelectionChanged = { [weak mainView, weak sidebar] display in
            sidebar?.setDisplaySelected(display != nil)
            sidebar?.inspector.connectedDisplays = (mainView?.connectedDisplays ?? []).map { (id: $0.displayID, name: $0.nickname) }
            let position = mainView?.selectedPosition()
            sidebar?.inspector.refresh(display, x: position?.x ?? 0, y: position?.y ?? 0)
            self.refreshOverlays()
        }
        mainView.onDisplayValuesChanged = { [weak inspector] display, x, y in
            inspector?.refresh(display, x: x, y: y)
            self.refreshOverlays()
            self.scheduleLivePreview()
        }

        let centerButton = NSButton(title: "Center View", target: mainView, action: #selector(DisplayArrangementView.centerView))
        let fitButton = NSButton(title: "Zoom to Fit", target: mainView, action: #selector(DisplayArrangementView.zoomToFitFromButton))
        centerButton.bezelStyle = .rounded
        fitButton.bezelStyle = .rounded
        let addVirtualButton = NSButton(title: "Add Virtual Display…", target: self, action: #selector(addVirtualDisplay))
        addVirtualButton.bezelStyle = .rounded
        let buttonStack = NSStackView(views: [centerButton, fitButton, addVirtualButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        let refreshButton = NSButton(title: "Refresh Displays", target: self, action: #selector(refreshDisplays))
        let settingsButton = NSButton(title: "Display Settings…", target: self, action: #selector(openDisplaySettings))
        refreshButton.bezelStyle = .rounded
        settingsButton.bezelStyle = .rounded
        let systemButtonStack = NSStackView(views: [refreshButton, settingsButton])
        systemButtonStack.orientation = .horizontal
        systemButtonStack.spacing = 8
        systemButtonStack.translatesAutoresizingMaskIntoConstraints = false

        // Identify and preview are modes that end on any click or key press.
        sidebarView = sidebar
        identifyButton.target = self; identifyButton.action = #selector(identifyToggled)
        previewButton.target = self; previewButton.action = #selector(previewToggled)
        liveCheckbox.target = self; liveCheckbox.action = #selector(liveToggled)
        overlays.clickThroughViews = [identifyButton, previewButton]
        overlays.onModesStopped = { [weak self] in
            self?.identifyButton.state = .off
            // A live preview isn't ended by clicks, so only a static one resets here.
            if self?.overlays.previewImages == nil { self?.previewButton.state = .off }
        }
        excludePrimaryCheckbox.target = self; excludePrimaryCheckbox.action = #selector(excludePrimaryToggled)
        let excluded = UserDefaults.standard.bool(forKey: Self.excludePrimaryKey)
        excludePrimaryCheckbox.state = excluded ? .on : .off
        overlays.excludePrimary = excluded
        self.mainView = mainView
        sidebar.exportImagesButton.target = self
        sidebar.exportImagesButton.action = #selector(exportWallpaperImages)
        sidebar.applyWallpaperButton.target = self
        sidebar.applyWallpaperButton.action = #selector(applyWallpaper)

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        mainView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(mainView)
        container.addSubview(sidebar)
        container.addSubview(buttonStack)
        container.addSubview(systemButtonStack)

        NSLayoutConstraint.activate([
            mainView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            mainView.trailingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            mainView.topAnchor.constraint(equalTo: container.topAnchor),
            mainView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            sidebar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sidebar.topAnchor.constraint(equalTo: container.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: SidebarMetrics.width),
            buttonStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            buttonStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            systemButtonStack.trailingAnchor.constraint(equalTo: mainView.trailingAnchor, constant: -12),
            systemButtonStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 680), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "ScreenBean"
        window.delegate = self
        window.contentView = container
        window.minSize = NSSize(width: 600, height: 400)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Re-reads the displays from macOS, e.g. after changing orientation in System Settings.
    @objc private func refreshDisplays() {
        mainView?.reloadDisplays()
        refreshOverlays()
    }

    // MARK: - Layout Presets

    private func rebuildPresetMenus() {
        let store = LayoutPresetStore.shared
        let actions: [(NSMenu, Selector)] = [(switchPresetMenu, #selector(applyPresetFromMenu(_:))), (renamePresetMenu, #selector(renamePresetFromMenu(_:))), (deletePresetMenu, #selector(deletePresetFromMenu(_:)))]
        for (menu, action) in actions {
            menu.removeAllItems()
            if store.presets.isEmpty {
                let empty = NSMenuItem(title: "No Saved Layouts", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                menu.addItem(empty)
                continue
            }
            for preset in store.presets {
                let item = NSMenuItem(title: preset.name, action: action, keyEquivalent: "")
                item.target = self
                item.representedObject = preset.id
                if menu === switchPresetMenu, preset.id == store.activeID { item.state = .on }
                menu.addItem(item)
            }
        }
    }

    /// Asks for a name in a small dialog. Returns nil if cancelled or left empty.
    private func promptForName(title: String, message: String, defaultName: String, button: String) -> String? {
        let field = NSTextField(string: defaultName)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.accessoryView = field
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private func presetFromMenu(_ sender: NSMenuItem) -> LayoutPreset? {
        (sender.representedObject as? UUID).flatMap { LayoutPresetStore.shared.preset(withID: $0) }
    }

    @objc private func savePreset() {
        guard let mainView else { return }
        let count = LayoutPresetStore.shared.presets.count + 1
        guard let name = promptForName(title: "Save Layout as Preset", message: "Saves where every display sits and how it looks, plus guides and image placement, so you can switch back to it later.", defaultName: "Layout \(count)", button: "Save") else { return }
        LayoutPresetStore.shared.add(mainView.makePreset(named: name))
    }

    @objc private func updateActivePreset() {
        guard let mainView, let active = LayoutPresetStore.shared.active else { return }
        let alert = NSAlert()
        alert.messageText = "Update \u{201C}\(active.name)\u{201D}?"
        alert.informativeText = "Replaces the saved layout with what is in the workspace now."
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        LayoutPresetStore.shared.update(active.id, with: mainView.makePreset(named: active.name))
    }

    @objc private func applyPresetFromMenu(_ sender: NSMenuItem) {
        guard let preset = presetFromMenu(sender) else { return }
        applyPreset(preset)
    }

    private func applyPreset(_ preset: LayoutPreset) {
        guard let mainView else { return }
        let missing = mainView.apply(preset)
        LayoutPresetStore.shared.activeID = preset.id
        refreshOverlays()
        scheduleLivePreview()
        if missing > 0 {
            showAlert("Some displays aren't connected", "\u{201C}\(preset.name)\u{201D} also had \(missing) display\(missing == 1 ? "" : "s") that aren't connected right now, so \(missing == 1 ? "it was" : "they were") left out.")
        }
    }

    @objc private func renamePresetFromMenu(_ sender: NSMenuItem) {
        guard let preset = presetFromMenu(sender),
              let name = promptForName(title: "Rename Layout", message: "", defaultName: preset.name, button: "Rename") else { return }
        LayoutPresetStore.shared.rename(preset.id, to: name)
    }

    @objc private func deletePresetFromMenu(_ sender: NSMenuItem) {
        guard let preset = presetFromMenu(sender) else { return }
        let alert = NSAlert()
        alert.messageText = "Delete \u{201C}\(preset.name)\u{201D}?"
        alert.informativeText = "The saved layout is removed. Your current workspace isn't changed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        LayoutPresetStore.shared.delete(preset.id)
    }

    /// A display was plugged in or removed: re-read the layout, then offer the saved preset for this set of displays.
    private func screenParametersChanged() {
        screenChangeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let mainView = self.mainView else { return }
            self.refreshDisplays()
            let store = LayoutPresetStore.shared
            let connected = Set(mainView.connectedDisplays.map(\.persistentID))
            let key = connected.sorted().joined(separator: ",")
            guard key != store.lastSuggestedSet else { return }
            store.lastSuggestedSet = key
            let matches = store.presets(matching: connected)
            guard let match = matches.first, !matches.contains(where: { $0.id == store.activeID }), self.window.isVisible else { return }
            let alert = NSAlert()
            alert.messageText = "Switch to \u{201C}\(match.name)\u{201D}?"
            alert.informativeText = "The connected displays match this saved layout."
            alert.addButton(withTitle: "Switch")
            alert.addButton(withTitle: "Not Now")
            alert.beginSheetModal(for: self.window) { response in
                if response == .alertFirstButtonReturn { self.applyPreset(match) }
            }
        }
        screenChangeWork = work
        // Displays settle for a moment after being plugged in.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    // MARK: - Virtual Displays

    @objc private func addVirtualDisplay() {
        guard let spec = VirtualDisplayPrompt.run() else { return }
        mainView?.addVirtualDisplay(name: spec.name, widthInches: spec.widthInches, heightInches: spec.heightInches, pixelWidth: spec.pixelWidth, pixelHeight: spec.pixelHeight)
        refreshOverlays()
    }

    @objc private func deleteVirtualDisplay() {
        mainView?.deleteSelectedVirtualDisplays()
        refreshOverlays()
    }

    // MARK: - Identify

    /// Pushes the current displays and selection to the overlays on the real screens.
    private func refreshOverlays() {
        guard let mainView else { return }
        overlays.update(
            displays: mainView.displays,
            selectedIDs: mainView.selectedDisplayIDs,
            guides: mainView.resolvedGuides(),
            panels: mainView.displayPanelRects()
        )
    }

    @objc private func identifyToggled() {
        overlays.identifyEnabled = identifyButton.state == .on
        refreshOverlays()
    }

    /// Shows each display's slice of the wallpaper full screen, spanning all displays.
    /// Live keeps it up and updating, under this window; otherwise it covers everything until the next click or key press.
    @objc private func previewToggled() {
        guard previewButton.state == .on else {
            endPreview()
            return
        }
        guard startPreview() else { previewButton.state = .off; return }
    }

    @objc private func liveToggled() {
        // Changing mode while a preview is up restarts it in the new mode.
        guard previewButton.state == .on else { return }
        if !startPreview() { previewButton.state = .off; endPreview() }
    }

    /// Returns false when there's no wallpaper to show.
    private func startPreview() -> Bool {
        let live = liveCheckbox.state == .on
        guard let export = wallpaperExportOrAlert(maxPixelWidth: live ? 1600 : nil) else { return false }
        refreshOverlays()
        overlays.showPreview(previewImages(from: export), live: live)
        // The window is raised above a live preview so the interface isn't covered.
        window.level = live ? NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1) : .normal
        return true
    }

    private func endPreview() {
        overlays.hidePreview()
        window.level = .normal
    }

    private func previewImages(from export: WallpaperExport) -> [CGDirectDisplayID: CGImage] {
        Dictionary(export.slices.map { ($0.displayID, $0.image) }, uniquingKeysWith: { first, _ in first })
    }

    /// Refreshes a live preview shortly after edits stop arriving.
    private func scheduleLivePreview() {
        guard previewButton.state == .on, liveCheckbox.state == .on else { return }
        liveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let export = self.mainView?.wallpaperExport(maxPixelWidth: 1600), !export.slices.isEmpty else { return }
            self.overlays.updatePreviewImages(self.previewImages(from: export))
        }
        liveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    @objc private func excludePrimaryToggled() {
        let excluded = excludePrimaryCheckbox.state == .on
        UserDefaults.standard.set(excluded, forKey: Self.excludePrimaryKey)
        overlays.excludePrimary = excluded
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlays.hideAll()
    }

    // MARK: - Measurements

    @objc private func toggleFractions() {
        MeasurementFormat.useFractions.toggle()
    }

    @objc private func toggleGapMeasurements() { GuideSettings.showGapMeasurements.toggle() }
    /// Turns edge and custom guides on together, or off if both are already on.
    @objc private func toggleGuides() {
        let allOn = GuideSettings.showEdgeGuides && GuideSettings.showCustomGuides
        GuideSettings.showEdgeGuides = !allOn
        GuideSettings.showCustomGuides = !allOn
    }
    @objc private func clearGuides() { UndoCenter.shared.perform("Clear Guides") { GuideStore.shared.removeAll() } }

    // MARK: - Undo

    @objc private func undoAction() { UndoCenter.shared.undo() }
    @objc private func redoAction() { UndoCenter.shared.redo() }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { UndoCenter.shared.manager }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(undoAction) {
            item.title = UndoCenter.shared.manager.canUndo ? UndoCenter.shared.manager.undoMenuItemTitle : "Undo"
            return UndoCenter.shared.manager.canUndo
        }
        if item.action == #selector(redoAction) {
            item.title = UndoCenter.shared.manager.canRedo ? UndoCenter.shared.manager.redoMenuItemTitle : "Redo"
            return UndoCenter.shared.manager.canRedo
        }
        if item.action == #selector(toggleGapMeasurements) { item.state = GuideSettings.showGapMeasurements ? .on : .off }
        if item.action == #selector(toggleGuides) { item.state = GuideSettings.showEdgeGuides && GuideSettings.showCustomGuides ? .on : .off }
        if item.action == #selector(deleteVirtualDisplay) { return mainView?.canDeleteSelectedVirtualDisplays ?? false }
        if item.action == #selector(updateActivePreset) {
            if let active = LayoutPresetStore.shared.active { item.title = "Update \u{201C}\(active.name)\u{201D} with Current Layout" } else { item.title = "Update Active Preset" }
            return LayoutPresetStore.shared.active != nil
        }
        if item.action == #selector(clearGuides) { return !GuideStore.shared.guides.isEmpty }
        if item.action == #selector(toggleFractions) {
            item.state = MeasurementFormat.useFractions ? .on : .off
        }
        return true
    }

    // MARK: - Wallpaper

    private func showAlert(_ title: String, _ message: String, style: NSAlert.Style = .informational) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.runModal()
    }

    private func wallpaperExportOrAlert(maxPixelWidth: Int? = nil) -> WallpaperExport? {
        guard let export = mainView?.wallpaperExport(maxPixelWidth: maxPixelWidth), !export.slices.isEmpty else {
            showAlert("No wallpaper", "Choose or drop a wallpaper image in the Spanned Wallpaper section first.")
            return nil
        }
        return export
    }

    private func sizeSummary(_ export: WallpaperExport) -> String {
        var lines = export.slices.map { "\($0.name): \($0.pixelWidth) × \($0.pixelHeight) px" }
        if export.isUpscaled {
            lines.append("\nThe wallpaper has \(Int(export.imagePixelsPerInch)) pixels per inch, but your sharpest display needs \(Int(export.neededPixelsPerInch)). It will be enlarged and may look soft.")
        }
        return lines.joined(separator: "\n")
    }

    private func pngData(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// A file-name-safe version of a display name.
    private func fileSafe(_ name: String) -> String {
        let cleaned = name.map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        return cleaned.isEmpty ? "Display" : cleaned
    }

    /// Saves one PNG per display, named after the display and sized to its native resolution.
    @objc private func exportWallpaperImages() {
        guard let export = wallpaperExportOrAlert() else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder for the wallpaper images, one per display."
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        var failures: [String] = []
        for (index, slice) in export.slices.enumerated() {
            let name = "\(fileSafe(slice.name))-\(slice.pixelWidth)x\(slice.pixelHeight)\(export.slices.count > 1 ? "-\(index + 1)" : "").png"
            do {
                guard let data = pngData(slice.image) else { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: folder.appendingPathComponent(name), options: .atomic)
            } catch {
                failures.append("\(slice.name): \(error.localizedDescription)")
            }
        }
        if failures.isEmpty {
            showAlert("Exported \(export.slices.count) image\(export.slices.count == 1 ? "" : "s")", sizeSummary(export))
        } else {
            showAlert("Some images could not be saved", failures.joined(separator: "\n"), style: .warning)
        }
    }

    /// Sets each display's desktop picture to its slice of the wallpaper.
    @objc private func applyWallpaper() {
        guard let export = wallpaperExportOrAlert() else { return }
        let confirm = NSAlert()
        confirm.messageText = "Apply wallpaper to \(export.slices.count) display\(export.slices.count == 1 ? "" : "s")?"
        confirm.informativeText = "This replaces the current desktop picture on each display.\n\n" + sizeSummary(export)
        confirm.addButton(withTitle: "Apply")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let folder = support.appendingPathComponent("ScreenBean/Wallpaper", isDirectory: true)
        // Clear earlier slices so the folder only holds the current set.
        try? FileManager.default.removeItem(at: folder)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { showAlert("Could not apply wallpaper", error.localizedDescription, style: .warning); return }

        let stamp = Int(Date().timeIntervalSince1970)
        var applied = 0
        var failures: [String] = []
        for slice in export.slices {
            // A virtual display has no screen to set a wallpaper on.
            if slice.isVirtual { continue }
            guard let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == slice.displayID }) else {
                failures.append("\(slice.name): not currently active (for example, mirrored)")
                continue
            }
            do {
                guard let data = pngData(slice.image) else { throw CocoaError(.fileWriteUnknown) }
                let url = folder.appendingPathComponent("\(fileSafe(slice.name))-\(stamp).png")
                try data.write(to: url, options: .atomic)
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
                    .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                    .allowClipping: false
                ])
                applied += 1
            } catch {
                failures.append("\(slice.name): \(error.localizedDescription)")
            }
        }
        if failures.isEmpty {
            showAlert("Wallpaper applied", "Set the desktop picture on \(applied) display\(applied == 1 ? "" : "s").")
        } else {
            showAlert("Applied to \(applied) of \(export.slices.count) displays", failures.joined(separator: "\n") + "\n\nYou can use Export Images and set the pictures in System Settings instead.", style: .warning)
        }
    }

    @objc private func openDisplaySettings() {
        // The Displays pane moved in macOS 13; fall back to the older identifier.
        let urls = ["x-apple.systempreferences:com.apple.Displays-Settings.extension", "x-apple.systempreferences:com.apple.preference.displays"]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }
}
