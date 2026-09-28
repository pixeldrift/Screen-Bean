//
//  DisplayView.swift
//  ScreenBean
//
//  Created by Nathan Pizar on 5/21/25.
//

import Cocoa

class DisplayView: NSView {
    var info: DisplayInfo
    var label: NSTextField!
    weak var delegate: DisplayViewDelegate?

    init(info: DisplayInfo) {
        self.info = info
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.systemBlue.cgColor
        layer?.borderColor = NSColor.black.cgColor
        layer?.cornerRadius = 5
        

        label = NSTextField(labelWithString: info.nickname)
        label.font = NSFont.boldSystemFont(ofSize: 14)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(editDisplayInfo))
        self.addGestureRecognizer(clickGesture)
    }

    @objc func editDisplayInfo() {
        delegate?.displayViewDidRequestEdit(self)
    }

    func updateInfo(_ newInfo: DisplayInfo) {
        self.info = newInfo
        label.stringValue = newInfo.nickname
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
