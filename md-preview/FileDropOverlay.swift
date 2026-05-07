//
//  FileDropOverlay.swift
//  md-preview
//
//  Drag-and-drop file open: drop a Markdown file anywhere in the window to
//  open it. Mirrors PageFlow's `.onDrop` + dashed-border overlay UX, in
//  AppKit. Installed as a full-bleed view in the window's content view; only
//  intercepts events while a drag is active, so it never blocks normal
//  clicks/scrolls.
//

import AppKit
import UniformTypeIdentifiers

/// Owns and installs the drop target view + overlay. AppDelegate creates one
/// per window and wires `onDropFile` to its file-open path.
final class FileDropController {

    /// Lowercased extensions accepted as Markdown.
    static let acceptedExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtxt", "mdtext", "txt"
    ]

    var onDropFile: ((URL) -> Void)? {
        didSet { dropView.onDropFile = onDropFile }
    }

    private weak var window: NSWindow?
    private let dropView = FileDropView()

    init(window: NSWindow) {
        self.window = window
        install()
    }

    private func install() {
        guard let contentView = window?.contentView else { return }
        dropView.translatesAutoresizingMaskIntoConstraints = false
        // Above all content so the overlay actually shows during a drag.
        contentView.addSubview(dropView, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            dropView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            dropView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            dropView.topAnchor.constraint(equalTo: contentView.topAnchor),
            dropView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }
}

// MARK: - FileDropView

/// Transparent view that accepts file-URL drags. While idle it returns `nil`
/// from `hitTest(_:)` so the underlying split view receives clicks; while a
/// drag is in progress its overlay child fades in to indicate the drop zone.
private final class FileDropView: NSView {

    var onDropFile: ((URL) -> Void)?

    private let overlay = DropOverlayView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        installOverlay()
    }

    required init?(coder: NSCoder) { nil }

    private func installOverlay() {
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.alphaValue = 0
        addSubview(overlay)
        let inset: CGFloat = 24
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            overlay.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            overlay.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            overlay.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset)
        ])
    }

    /// Click-through while idle. NSDraggingDestination methods still fire
    /// because drag routing is independent of `hitTest(_:)`.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasAcceptableMarkdownURL(in: sender) else { return [] }
        setOverlayVisible(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasAcceptableMarkdownURL(in: sender) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setOverlayVisible(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        setOverlayVisible(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hasAcceptableMarkdownURL(in: sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { setOverlayVisible(false) }
        guard let url = firstAcceptableMarkdownURL(in: sender) else { return false }
        onDropFile?(url)
        return true
    }

    // MARK: Helpers

    private func hasAcceptableMarkdownURL(in info: NSDraggingInfo) -> Bool {
        firstAcceptableMarkdownURL(in: info) != nil
    }

    private func firstAcceptableMarkdownURL(in info: NSDraggingInfo) -> URL? {
        let pb = info.draggingPasteboard
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: options) as? [URL] else {
            return nil
        }
        return urls.first { isMarkdown(url: $0) }
    }

    private func isMarkdown(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if FileDropController.acceptedExtensions.contains(ext) { return true }
        // Fall back to UTI for files declared as Markdown but with unusual
        // extensions (`net.daringfireball.markdown` / `public.markdown`).
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            if type.conforms(to: UTType("net.daringfireball.markdown") ?? .plainText) { return true }
            if type.conforms(to: UTType("public.markdown") ?? .plainText) { return true }
        }
        return false
    }

    private func setOverlayVisible(_ visible: Bool) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.allowsImplicitAnimation = true
            overlay.animator().alphaValue = visible ? 1 : 0
        }
    }
}

// MARK: - DropOverlayView

/// The visual feedback shown during a drag: rounded rect with dashed white
/// border over a dimmed black backdrop, and a centered icon + label stack.
/// Matches PageFlow's `dropTargetOverlay` styling.
private final class DropOverlayView: NSView {

    private static let cornerRadius: CGFloat = 16
    private static let dashPattern: [NSNumber] = [8, 8]
    private static let lineWidth: CGFloat = 2

    private let backdropLayer = CALayer()
    private let borderLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.2
        layer?.shadowRadius = 16
        layer?.shadowOffset = CGSize(width: 0, height: -6)
        layer?.masksToBounds = false
        buildBackdrop()
        buildBorder()
        buildContent()
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { false }

    /// Pure visual feedback — never intercepts events.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func buildBackdrop() {
        backdropLayer.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        backdropLayer.cornerRadius = Self.cornerRadius
        layer?.addSublayer(backdropLayer)
    }

    private func buildBorder() {
        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.strokeColor = NSColor.white.withAlphaComponent(0.65).cgColor
        borderLayer.lineWidth = Self.lineWidth
        borderLayer.lineDashPattern = Self.dashPattern
        layer?.addSublayer(borderLayer)
    }

    private func buildContent() {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "arrow.down.doc",
                             accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 28, weight: .semibold)
        icon.contentTintColor = .white

        let title = NSTextField(labelWithString: "Drop Markdown to Open")
        title.font = .systemFont(ofSize: NSFont.systemFontSize(for: .regular) + 3, weight: .semibold)
        title.textColor = .white

        let subtitle = NSTextField(labelWithString: "Drag a Markdown file anywhere in the window")
        subtitle.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.75)

        let stack = NSStackView(views: [icon, title, subtitle])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    override func layout() {
        super.layout()
        backdropLayer.frame = bounds
        let inset = Self.lineWidth / 2
        let borderRect = bounds.insetBy(dx: inset, dy: inset)
        borderLayer.frame = bounds
        borderLayer.path = CGPath(
            roundedRect: borderRect,
            cornerWidth: Self.cornerRadius,
            cornerHeight: Self.cornerRadius,
            transform: nil
        )
    }
}
