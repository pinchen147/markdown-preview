//
//  TrafficLightsView.swift
//  md-preview
//
//  Custom traffic lights styled like PageFlow's: three colored circles inside an
//  ultra-thin material capsule. Designed to be revealed on hover by
//  WindowChromeController; the system buttons are hidden.
//

import AppKit

final class TrafficLightsView: NSView {

    static let buttonDiameter: CGFloat = 12
    static let buttonSpacing: CGFloat = 8
    static let containerPadding: CGFloat = 8
    static let cornerRadius: CGFloat = 14

    var onClose: (() -> Void)?
    var onMinimize: (() -> Void)?
    var onZoom: (() -> Void)?

    private let blur = NSVisualEffectView()
    private let tint = NSView()
    private let border = NSView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.1
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        buildBackground()
        buildButtons()
    }

    required init?(coder: NSCoder) { nil }

    // Hide hit testing while invisible so the buttons can't swallow clicks
    // while the chrome is faded out.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard alphaValue > 0.01 else { return nil }
        return super.hitTest(point)
    }

    // The chrome lives in the title bar drag region. macOS treats unclaimed
    // pixels in that region as window-drag handles, so we must opt out.
    override var mouseDownCanMoveWindow: Bool { false }

    private func buildBackground() {
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.material = .hudWindow
        blur.blendingMode = .withinWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = Self.cornerRadius
        blur.layer?.masksToBounds = true
        addSubview(blur)

        tint.translatesAutoresizingMaskIntoConstraints = false
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor(white: 0.196, alpha: 0.12).cgColor
        tint.layer?.cornerRadius = Self.cornerRadius
        addSubview(tint)

        border.translatesAutoresizingMaskIntoConstraints = false
        border.wantsLayer = true
        border.layer?.cornerRadius = Self.cornerRadius
        border.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        border.layer?.borderWidth = 1
        addSubview(border)

        for layer in [blur, tint, border] {
            NSLayoutConstraint.activate([
                layer.leadingAnchor.constraint(equalTo: leadingAnchor),
                layer.trailingAnchor.constraint(equalTo: trailingAnchor),
                layer.topAnchor.constraint(equalTo: topAnchor),
                layer.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }

    private func buildButtons() {
        let close = TrafficLightButton(color: .systemRed) { [weak self] in self?.onClose?() }
        let mini = TrafficLightButton(color: .systemYellow) { [weak self] in self?.onMinimize?() }
        let zoom = TrafficLightButton(color: .systemGreen) { [weak self] in self?.onZoom?() }

        let stack = NSStackView(views: [close, mini, zoom])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.spacing = Self.buttonSpacing
        stack.alignment = .centerY
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.containerPadding),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.containerPadding),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: Self.containerPadding),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.containerPadding)
        ])
    }
}

private final class TrafficLightButton: NSControl {
    private let color: NSColor
    private let onClick: () -> Void

    init(color: NSColor, onClick: @escaping () -> Void) {
        self.color = color
        self.onClick = onClick
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = TrafficLightsView.buttonDiameter / 2
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: TrafficLightsView.buttonDiameter),
            heightAnchor.constraint(equalToConstant: TrafficLightsView.buttonDiameter)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        // Tap-to-fire: dispatch on click without waiting for mouseUp so the
        // window action runs even if the cursor drifts off the 12pt circle.
        onClick()
    }
}
