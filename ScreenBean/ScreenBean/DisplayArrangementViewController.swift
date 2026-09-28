//
//  DisplayArrangementViewController.swift
//  ScreenBean
//
//  Created by Nathan Pizar on 5/21/25.
//

import Cocoa

protocol DisplayViewDelegate: AnyObject {
    func displayViewDidRequestEdit(_ displayView: DisplayView)
}

class DisplayArrangementViewController: NSViewController {
    var displayViews: [DisplayView] = []
    var showingInches = false

    override func loadView() {
        let mainView = NSView()
        
        mainView.translatesAutoresizingMaskIntoConstraints = false

        mainView.wantsLayer = true
        mainView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // Add toggle button
        let toggleButton = NSButton(checkboxWithTitle: "Actual Size", target: self, action: #selector(toggleInchesMode))
        toggleButton.setButtonType(.switch)
        toggleButton.frame = NSRect(x: 20, y: 20, width: 200, height: 30)
        mainView.addSubview(toggleButton)

        self.view = mainView

        setupDisplays()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Set a background color to visually confirm this view controller is showing
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemTeal.cgColor
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        print("View frame: \(view.frame), bounds: \(view.bounds)")
        layoutDisplayViews()
    }

    func setupDisplays() {
        let displays = DisplayInfo.detectDisplays()
        displayViews = []

        for info in displays {
            let displayView = DisplayView(info: info)
            displayView.delegate = self
            view.addSubview(displayView)
            displayViews.append(displayView)
        }
    }

    func layoutDisplayViews() {
        let scaleFactor: CGFloat = 0.1
        let spacing: CGFloat = 40

        let widths = displayViews.map { CGFloat($0.info.pixelWidth) * scaleFactor }
        let totalWidth = widths.reduce(0, +) + spacing * CGFloat(displayViews.count - 1)

        let containerWidth = view.bounds.width
        let containerHeight = view.bounds.height

        var xOffset = (containerWidth - totalWidth) / 2

        for displayView in displayViews {
            let info = displayView.info
            let width = CGFloat(info.pixelWidth) * scaleFactor
            let height = CGFloat(info.pixelHeight) * scaleFactor
            let yCentered = (containerHeight - height) / 2

            displayView.frame = CGRect(x: xOffset, y: yCentered, width: width, height: height)
            xOffset += width + spacing
        }
    }

    @objc func toggleInchesMode(_ sender: NSButton) {
        showingInches = (sender.state == .on)
        // Implement update logic if needed for inches mode
        layoutDisplayViews()
    }
}

extension DisplayArrangementViewController: DisplayViewDelegate {
    
    func displayViewDidRequestEdit(_ displayView: DisplayView) {
        let editor = DisplayEditViewController(info: displayView.info)
        editor.completionHandler = { updatedInfo in
            displayView.updateInfo(updatedInfo)
            self.layoutDisplayViews()
        }

        presentAsModalWindow(editor)
    }
}

