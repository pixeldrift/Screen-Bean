//
//  ImageDropViews.swift
//  ScreenBean
//
//  Views that accept image files dragged from Finder.
//

import Cocoa
import UniformTypeIdentifiers

/// Reads dropped image file URLs from a drag.
private func droppedImageURLs(_ info: NSDraggingInfo) -> [URL] {
    let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true, .urlReadingContentsConformToTypes: [UTType.image.identifier]]
    return info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
}

/// A box that shows an image, or "Drop Image Here" when empty. Click to browse.
final class ImageDropView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var onDropURL: ((URL) -> Void)?
    var onClick: (() -> Void)?
    private var isTargeted = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { super.init(coder: coder); registerForDraggedTypes([.fileURL]) }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6)
        (isTargeted ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.textBackgroundColor.withAlphaComponent(0.4)).setFill()
        path.fill()
        if let image, image.size.width > 0, image.size.height > 0 {
            let fit = min(box.width / image.size.width, box.height / image.size.height)
            let size = NSSize(width: image.size.width * fit, height: image.size.height * fit)
            image.draw(in: NSRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height))
        } else {
            let style = NSMutableParagraphStyle(); style.alignment = .center
            let text = "Drop Image Here" as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: style]
            let height = text.size(withAttributes: attrs).height
            text.draw(in: NSRect(x: box.minX, y: box.midY - height / 2, width: box.width, height: height), withAttributes: attrs)
        }
        path.lineWidth = isTargeted ? 2 : 1
        if image == nil { path.setLineDash([4, 3], count: 2, phase: 0) }
        (isTargeted ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !droppedImageURLs(sender).isEmpty else { return [] }
        isTargeted = true
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { isTargeted = false }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isTargeted = false
        guard let url = droppedImageURLs(sender).first else { return false }
        onDropURL?(url)
        return true
    }
}

/// A button that also accepts an image file dropped on it.
final class DropButton: NSButton {
    var onDropURL: ((URL) -> Void)?

    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { super.init(coder: coder); registerForDraggedTypes([.fileURL]) }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !droppedImageURLs(sender).isEmpty else { return [] }
        isHighlighted = true
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { isHighlighted = false }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isHighlighted = false
        guard let url = droppedImageURLs(sender).first else { return false }
        onDropURL?(url)
        return true
    }
}
