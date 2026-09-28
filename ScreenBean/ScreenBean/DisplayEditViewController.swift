//
//  DisplayEditViewController.swift
//  ScreenBean
//
//  Created by Nathan Pizar on 5/21/25.
//

import Cocoa

class DisplayEditViewController: NSViewController {
    var info: DisplayInfo
    var completionHandler: ((DisplayInfo) -> Void)?

    init(info: DisplayInfo) {
        self.info = info
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let panel = NSView()
        panel.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
        panel.layer?.backgroundColor = NSColor.systemTeal.cgColor
        
        self.view = panel
        self.view.window?.makeFirstResponder(nil)
    }
    

    @objc func modeChanged(_ sender: NSSegmentedControl) {
        let isDiagonal = sender.selectedSegment == 1
        for subview in view.subviews {
            if let textField = subview as? NSTextField, textField.placeholderString == "Diagonal" {
                textField.isHidden = !isDiagonal
            }
            if let textField = subview as? NSTextField, textField.placeholderString == "Width" || textField.placeholderString == "Height" {
                textField.isHidden = isDiagonal
            }
        }
    }

    @objc func toggleBezelFields(_ sender: NSButton) {
        let unlink = sender.state == .on
        for subview in view.subviews {
            if let textField = subview as? NSTextField, ["Top", "Bottom", "Left", "Right"].contains(textField.placeholderString ?? "") {
                textField.isHidden = !unlink
            }
        }
    }

    @objc func saveChanges() {
        var updatedInfo = info

        for subview in view.subviews {
            if let field = subview as? NSTextField {
                switch field.placeholderString {
                case "Width":
                    updatedInfo.physicalWidthInches = Double(field.stringValue) ?? updatedInfo.physicalWidthInches
                case "Height":
                    updatedInfo.physicalHeightInches = Double(field.stringValue) ?? updatedInfo.physicalHeightInches
                case "Diagonal":
                    let diagonal = Double(field.stringValue) ?? 0
                    if diagonal > 0 {
                        let aspect = info.aspectRatio
                        updatedInfo.physicalHeightInches = sqrt(pow(diagonal, 2) / (1 + pow(aspect, 2)))
                        updatedInfo.physicalWidthInches = aspect * updatedInfo.physicalHeightInches
                    }
                default:
                    break
                }
            } else if let checkbox = subview as? NSButton, checkbox.title == "Make Primary" {
                updatedInfo.isPrimary = (checkbox.state == .on)
            } else if let textField = subview as? NSTextField, textField.placeholderString == nil, textField.stringValue != info.nickname {
                updatedInfo.nickname = textField.stringValue
            }
        }

        completionHandler?(updatedInfo)
        dismiss(self)
    }
}
