//
//  WindowChromeController.swift
//  md-preview
//
//  Hides the standard window chrome and reveals the toolbar (which holds the
//  custom glass-capsule traffic lights as its first item) on hover near the
//  top of the window — matching PageFlow's UX with native NSToolbar layout.
//

import AppKit

final class WindowChromeController: NSObject {

    /// Vertical zone at the top of the window that triggers the chrome
    /// reveal. Wide enough that the cursor can travel from above the title
    /// bar down to any toolbar item without re-triggering exit.
    static let hoverZoneHeight: CGFloat = 52

    /// Height of the title-bar drag strip. Matches the hover zone so the
    /// entire chrome area drags the window — empty space, between toolbar
    /// pills, anywhere up there. Toolbar items still take click priority
    /// because they live in the title-bar layer (above contentView), and
    /// the drop overlay still routes drags via its registered drag types.
    static let dragZoneHeight: CGFloat = 52

    private weak var window: NSWindow?
    private let hoverTracker = HoverTrackingView()
    private let windowDragArea = WindowDragView()

    /// Multiple independent reasons can pin the chrome open at once (access
    /// banner, search-field focus, etc.). The chrome reveals when any pin is
    /// active OR the cursor is in the hover zone.
    private var pinReasons: Set<String> = []

    private var isHovering: Bool = false {
        didSet {
            guard oldValue != isHovering else { return }
            applyVisibility()
        }
    }

    /// Hold the chrome open under a named reason. Repeat calls with the same
    /// reason are idempotent. Pair every call with `unpin(_:)`.
    func pin(_ reason: String) {
        let inserted = pinReasons.insert(reason).inserted
        if inserted { applyVisibility() }
    }

    func unpin(_ reason: String) {
        let removed = pinReasons.remove(reason) != nil
        if removed { applyVisibility() }
    }

    init(window: NSWindow) {
        self.window = window
        super.init()
        configureWindow()
        installHoverTracker()
        observeWindowChanges()
        applyVisibility()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Window setup

    private func configureWindow() {
        guard let window else { return }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarSeparatorStyle = .none

        hideSystemButtons()
    }

    /// Hide the close/min/zoom buttons. Re-applied on multiple notifications
    /// because AppKit re-shows them when toolbar visibility, key state, or
    /// full-screen state changes — once-at-startup is not enough.
    private func hideSystemButtons() {
        guard let window else { return }
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            let button = window.standardWindowButton(kind)
            button?.isHidden = true
            button?.alphaValue = 0
        }
    }

    private func observeWindowChanges() {
        let nc = NotificationCenter.default
        let names: [NSNotification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.didUpdateNotification
        ]
        for name in names {
            nc.addObserver(
                self,
                selector: #selector(windowStateChanged),
                name: name,
                object: window
            )
        }
    }

    @objc private func windowStateChanged() {
        hideSystemButtons()
    }

    private func installHoverTracker() {
        guard let contentView = window?.contentView else { return }

        // Tracking strip sits above all content so it always sees mouse moves
        // within the top zone, even over child controls. Hit testing is
        // disabled so it never swallows clicks. Tracking-area events fire
        // regardless of hit testing, so this still detects hover correctly.
        hoverTracker.translatesAutoresizingMaskIntoConstraints = false
        hoverTracker.onHoverChange = { [weak self] hovering in
            self?.isHovering = hovering
        }
        contentView.addSubview(hoverTracker, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            hoverTracker.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hoverTracker.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            hoverTracker.topAnchor.constraint(equalTo: contentView.topAnchor),
            hoverTracker.heightAnchor.constraint(equalToConstant: Self.hoverZoneHeight)
        ])

        // With `automaticallyAdjustsContentInsets = false`, the document view
        // extends right under the title bar and swallows mouse-down events
        // there. Sit a transparent drag strip on top so the user can still
        // drag the window from the title bar area, like PageFlow does.
        windowDragArea.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(windowDragArea, positioned: .above, relativeTo: hoverTracker)
        NSLayoutConstraint.activate([
            windowDragArea.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            windowDragArea.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            windowDragArea.topAnchor.constraint(equalTo: contentView.topAnchor),
            windowDragArea.heightAnchor.constraint(equalToConstant: Self.dragZoneHeight)
        ])
    }

    // MARK: - Reveal / hide

    private var shouldReveal: Bool { isHovering || !pinReasons.isEmpty }

    private func applyVisibility() {
        let reveal = shouldReveal
        if let toolbar = window?.toolbar, toolbar.isVisible != reveal {
            toolbar.isVisible = reveal
        }
        // Toolbar isVisible toggling re-shows the system buttons; re-hide on
        // the next runloop tick after AppKit has re-laid-out the title bar.
        DispatchQueue.main.async { [weak self] in self?.hideSystemButtons() }
    }
}

// MARK: - WindowDragView

/// Transparent strip at the top of the window that explicitly drives the
/// window drag via `NSWindow.performDrag(with:)`. Restores the title-bar
/// drag affordance that's lost when content extends under the toolbar (no
/// auto content insets). Same role as PageFlow's `WindowDragArea`.
///
/// `mouseDownCanMoveWindow` is a heuristic AppKit checks before forwarding a
/// drag — but it's ignored when any ancestor (e.g. `NSScrollView` /
/// `WKWebView`) registers gesture recognizers for clicks. `performDrag` is
/// the explicit Apple API that always works.
private final class WindowDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

// MARK: - HoverTrackingView

/// Transparent NSView whose only job is to fire a callback when the cursor
/// enters or exits its bounds. Same pattern as PageFlow's HoverTrackingArea.
private final class HoverTrackingView: NSView {
    var onHoverChange: ((Bool) -> Void)?

    private var trackingArea: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .enabledDuringMouseDrag, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            onHoverChange?(false)
        }
    }

    // Click-through: never intercept events for sibling views.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
